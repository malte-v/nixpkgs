{ pkgs, lib, config, ... }:

with lib;

# TODO
# * general networking (imperative)
# * DNS
#   * DHCP setzt Records
# * MACVLAN
# * Isolation
# * Migration
# * rootfs

let
  cfg = config.nixos.containers.instances;

  yesNo = x: if x then "yes" else "no";
  ifacePrefix = type: if type == "veth" then "ve" else "vz";

  mkRadvdSection = type: name: v6Pool:
    assert elem type [ "veth" "zone" ];
    ''
      interface ${ifacePrefix type}-${name} {
        AdvSendAdvert on;
        ${flip concatMapStrings v6Pool (x: ''
          prefix ${x} {
            AdvOnLink on;
            AdvAutonomous on;
          };
        '')}
      };
    '';

  mkMatchCfg = type: name:
    assert elem type [ "veth" "zone" ]; {
      Name = "${ifacePrefix type}-${name}";
      Driver = if type == "veth" then "veth" else "bridge";
    };

  mkNetworkCfg = dhcp: nat: {
    LinkLocalAddressing = "yes";
    DHCPServer = yesNo dhcp;
    IPMasquerade = yesNo nat;
    IPForward = "yes";
    LLDP = "yes";
    EmitLLDP = "customer-bridge";
    IPv6AcceptRA = "no";
  };

  recUpdate3 = a: b: c:
    recursiveUpdate a (recursiveUpdate b c);

  mkStaticNetOpts = v:
    assert elem v [ 4 6 ]; {
      "v${toString v}".static = {
        hostAddresses = mkOption {
          default = [];
          type = types.listOf types.str;
          example = literalExample (
            if v == 4 then ''[ "10.151.1.1/24" ]''
            else ''[ "fd23::/64" ]''
          );
          description = ''
            Address of the container on the host-side, i.e. the
            subnet and address assigned to <literal>ve-&lt;name&gt;</literal>.
          '';
        };
        containerPool = mkOption {
          default = [];
          type = types.listOf types.str;
          example = literalExample (
            if v == 4 then ''[ "10.151.1.2/24" ]''
            else ''[ "fd23::2/64" ]''
          );

          description = ''
            Addresses to be assigned to the container, i.e. the
            subnet and address assigned to the <literal>host0</literal>-interface.
          '';
        };
      };
    };

  mkNetworkingOpts = type:
    let
      mkIPOptions = v: assert elem v [ 4 6 ]; {
        addrPool = mkOption {
          type = types.listOf types.str;
          default = if v == 4
            then [ "0.0.0.0/${toString (if type == "zone" then 24 else 28)}" ]
            else [ "::/64" ];

          description = ''
            Address pool to assign to a network. If
            <literal>::/64</literal> or <literal>0.0.0.0/24</literal> is specified,
            <citerefentry><refentrytitle>systemd.network</refentrytitle><manvolnum>5</manvolnum>
            </citerefentry> will assign an ULA IPv6 or private IPv4 address from
            the address-pool of the given size to the interface.

            Please note that NATv6 is currently not supported since <literal>IPMasquerade</literal>
            doesn't support IPv6. If this is still needed, it's recommended to do it like this:

            <screen>
            <prompt># </prompt>ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
            </screen>
          '';
        };
      } // (optionalAttrs (v == 4) {
        nat = mkOption {
          default = true;
          type = types.bool;
          description = ''
            Whether to set-up a basic NAT to enable internet access for the nspawn containers.
          '';
        };
      });
    in
      assert elem type [ "veth" "zone" ]; {
        v4 = mkIPOptions 4;
        v6 = mkIPOptions 6;
      };

  mkImage = name: config:
    { container = import "${config.nixpkgs}/nixos/lib/eval-config.nix" {
        system = pkgs.system;
        modules = [
          ({ pkgs, ... }: {
            boot.isContainer = true;
            networking = {
              hostName = name;
              useHostResolvConf = false;
              useDHCP = false;
              useNetworkd = true;
            };
            systemd.network.networks."20-host0" = {
              matchConfig = {
                Virtualization = "container";
                Name = "host0";
              };
              dhcpConfig.UseTimezone = "yes";
              networkConfig = {
                DHCP = "yes";
                LLDP = "yes";
                EmitLLDP = "customer-bridge";
                LinkLocalAddressing = "yes";
              };
              address = mkIf (cfg.${name}.network != null) (
                cfg.${name}.network.v4.static.containerPool
                ++ cfg.${name}.network.v6.static.containerPool
              );
            };
          })
        ] ++ (config.config);
        prefix = [ "nixos" "containers" "instances" name "config" ];
      };
      inherit config;
    };

  mkContainer = cfg: let inherit (cfg) container config; in mkMerge [{
    execConfig = mkMerge [
      {
        Boot = false;
        Parameters = "${container.config.system.build.toplevel}/init";
        Ephemeral = yesNo config.ephemeral;
      }
      (mkIf (!config.ephemeral) {
        LinkJournal = mkDefault "guest";
      })
    ];
    filesConfig = mkIf config.sharedNix {
      BindReadOnly = [ "/nix/store" "/nix/var/nix/db" "/nix/var/nix/daemon-socket" ];
    };
    networkConfig = mkMerge [
      { Private = true;
        VirtualEthernet = "yes";
      }
      (mkIf (config.zone != null) {
        Zone = config.zone;
      })
    ];
  } (mkIf (!config.sharedNix) {
    extraDrvConfig = let
      info = pkgs.closureInfo {
        rootPaths = [ container.config.system.build.toplevel ];
      };
    in pkgs.runCommand "bindmounts.nspawn" { }
      ''
        touch $out
        echo "[Files]" > $out

        cat ${info}/store-paths | while read line
        do
          echo "BindReadOnly=$line" >> $out
        done
      '';
  })];

  images = mapAttrs mkImage cfg;
in {
  options.nixos.containers = {
    zones = mkOption {
      type = types.attrsOf (types.submodule {
        options = mkNetworkingOpts "zone";
      });
      default = {};
      description = ''
        Networking zones for nspawn containers. In this mode, the host-side
        of the virtual ethernet of a machine is managed by an interface named
        <literal>vz-&lt;name&gt;</literal>.
      '';
    };

    instances = mkOption {
      default = {};
      type = types.attrsOf (types.submodule {
        options = {
          sharedNix = mkOption {
            default = true;
            type = types.bool;
            description = ''
              <warning>
                <para>Experimental setting! Expect things to break!</para>
              </warning>

              With this option <emphasis>disabled</emphasis>, only the needed store-paths will
              be mounted into the container rather than the entire store.
            '';
          };

          ephemeral = mkEnableOption "ephemeral container" // {
            description = ''
              <literal>ephemeral</literal> means that the container's rootfs will be wiped
              before every startup. See <citerefentry><refentrytitle>systemd.nspawn</refentrytitle>
              <manvolnum>5</manvolnum></citerefentry> for further context.
            '';
          };

          nixpkgs = mkOption {
            default = pkgs.path;
            type = types.path;
            description = ''
              Path to the `nixpkgs`-checkout or channel to use for the container.
            '';
          };

          zone = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Name of the networking zone defined by <citerefentry>
              <refentrytitle>systemd.nspawn</refentrytitle><manvolnum>5</manvolnum></citerefentry>.
              Please note that this is mutually exclusive with the <option>network</option>-option.
            '';
          };

          network = mkOption {
            type = types.nullOr (types.submodule {
              options = recUpdate3
                (mkNetworkingOpts "veth")
                (mkStaticNetOpts 4)
                (mkStaticNetOpts 6);
            });
            default = null;
            description = ''
              Networking options for a single container. With this option used, a
              <literal>veth</literal>-pair is created. It's possible to configure a dynamically
              managed network with private IPv4 and ULA IPv6 the same way like zones.
              Additionally, it's possible to statically assign addresses to a container here.
            '';
          };

          config = mkOption {
            description = ''
              NixOS configuration for the container. See <citerefentry>
              <refentrytitle>configuration.nix</refentrytitle><manvolnum>5</manvolnum>
              </citerefentry> for available options.
            '';
            default = {};
            type = mkOptionType {
              name = "NixOS configuration";
              merge = const (map (x: rec { imports = [ x.value ]; key = _file; _file = x.file; }));
            };
          };
        };
      });

      description = ''
        Attribute set to define <citerefentry><refentrytitle>systemd.nspawn</refentrytitle>
        <manvolnum>5</manvolnum></citerefentry>-managed containers. With this attribute-set,
        a network, a shared store and a NixOS configuration can be declared for each running
        container.

        The container's state is managed in <filename>/var/lib/machines/&lt;name&gt;</filename>.
        A machine can be started with the
        <filename>systemd-nspawn@&lt;name&gt;.service</filename>-unit, during runtime it can
        be accessed with <citerefentry><refentrytitle>machinectl</refentrytitle>
        <manvolnum>1</manvolnum></citerefentry>.
      '';
    };
  };

  config = mkIf (cfg != {}) {
    assertions = [
      { assertion = !config.boot.isContainer;
        description = ''
          Cannot start containers inside a container!
        '';
      }
    ] ++ (flip concatMap (attrNames config.nixos.containers.instances) (n: let inst = cfg.${n}; in [
      { assertion = inst.zone == null && inst.network != null || inst.zone != null && inst.network == null;
        message = ''
          The options `zone' and `network' are mutually exclusive!
          (Invalid container: ${n})
        '';
      }
      { assertion = inst.zone != null -> (config.nixos.containers.zones != null && config.nixos.containers.zones ? ${inst.zone});
        message = ''
          No configuration found for zone `${inst.zone}'!
          (Invalid container: ${n})
        '';
      }
    ]));

    services.radvd = {
      enable = true;
      config = ''
        ${concatMapStrings
          (x: mkRadvdSection "veth" x cfg.${x}.network.v6.addrPool)
          (filter
            (n: cfg.${n}.network != null)
            (attrNames cfg))
        }
        ${concatMapStrings
          (x: mkRadvdSection "zone" x config.nixos.containers.zones.${x}.v6.addrPool)
          (attrNames config.nixos.containers.zones)
        }
      '';
    };

    systemd = {
      network.networks = mkMerge
        ((flip mapAttrsToList cfg (name: config: optionalAttrs (config.network != null) {
          "20-${ifacePrefix "veth"}-${name}" = {
            matchConfig = mkMatchCfg "veth" name;
            address = config.network.v4.addrPool
              ++ config.network.v6.addrPool
              ++ optionals (config.network.v4.static.hostAddresses != null)
                config.network.v4.static.hostAddresses
              ++ optionals (config.network.v6.static.hostAddresses != null)
                config.network.v6.static.hostAddresses;
            networkConfig = mkNetworkCfg (config.network.v4.addrPool != []) config.network.v4.nat;
          };
        }))
        ++ (flip mapAttrsToList config.nixos.containers.zones (name: zone: {
          "20-${ifacePrefix "zone"}-${name}" = {
            matchConfig = mkMatchCfg "zone" name;
            address = zone.v4.addrPool ++ zone.v6.addrPool;
            networkConfig = mkNetworkCfg true zone.v4.nat;
          };
        })));

      nspawn = mapAttrs (const mkContainer) images;
      targets.machines.wants = map (x: "systemd-nspawn@${x}.service") (attrNames cfg);
      services = listToAttrs (flip map (attrNames cfg) (container:
        nameValuePair "systemd-nspawn@${container}" {
          preStart = mkBefore ''
            mkdir -p /var/lib/machines/${container}/{etc,var}
            touch /var/lib/machines/${container}/etc/{os-release,machine-id} || true
          '';
        }
      ));
    };
  };
}
