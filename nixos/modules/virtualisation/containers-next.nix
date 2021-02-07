{ pkgs, lib, config, ... }:

with lib;

# TODO
# * networking
#   * slaac
#   * static
#   * zones (only slaac)
#   * public prefix testen
# * refactor/simplify
# * general networking (imperative)
# * DNS
#   * DHCP setzt Records
# * MACVLAN
# * Isolation
# * Migration
# * rootfs

let
  cfg = config.nixos.containers.instances;

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

  mkNetworkCfg = nat: {
    LinkLocalAddressing = "yes";
    DHCPServer = "yes";
    IPMasquerade = if nat then "yes" else "no";
    LLDP = "yes";
    EmitLLDP = "customer-bridge";
    IPv6AcceptRA = "no";
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
          '';
        };
        nat = mkOption {
          default = v == 4;
          type = types.bool;
          description = ''
            Whether to set-up a basic NAT to enable internet access for the nspawn containers.
          '';
        };
      };
    in
      assert elem type [ "veth" "zone" ]; {
        v4 = mkIPOptions 4;
        v6 = mkIPOptions 6;
      };

  mkImage = name: config:
    { container = import "${config.nixpkgs}/nixos/lib/eval-config.nix" {
        system = builtins.currentSystem;
        modules = [
          ({ pkgs, ... }: {
            boot.isContainer = true;
            networking = {
              hostName = name;
              useHostResolvConf = false;
              useDHCP = false;
              useNetworkd = true;
            };
          })
        ] ++ (config.config);
        prefix = [ "nixos" "containers" "instances" name "config" ];
      };
      inherit config;
    };

  mkContainer = cfg: let inherit (cfg) container config; in mkMerge [{
    execConfig = {
      Boot = false;
      Parameters = "${container.config.system.build.toplevel}/init";
      LinkJournal = "guest";
    };
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
        Networking zones for nspawn containers.
      '';
    };

    instances = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          sharedNix = mkOption {
            default = true;
            type = types.bool;
            description = ''
              NOTE: experimental setting! Expect things to break!

              With this option *disabled*, only the needed store-paths will
              be mounted into the container rather than the entire store.
            '';
          };

          nixpkgs = mkOption {
            default = <nixpkgs>;
            type = types.path;
            description = ''
              Path to the `nixpkgs`-checkout or channel to use for the container.
            '';
          };

          zone = mkOption {
            type = types.nullOr types.str;
            default = null;
          };

          network = mkOption {
            type = types.nullOr (types.submodule {
              options = mkNetworkingOpts "veth";
            });
            default = null;
          };

          config = mkOption {
            description = ''
              NixOS configuration for the container.
            '';
            default = {};
            type = mkOptionType {
              name = "NixOS configuration";
              merge = const (map (x: rec { imports = [ x.value ]; key = _file; _file = x.file; }));
            };
          };
        };
      });
    };
  };

  config = mkIf (cfg != {}) {
    assertions = flip concatMap (attrValues config.nixos.containers.instances) (inst: [
      { assertion = inst.zone != inst.network;
        message = ''
          It's not supported to set both `zone' and `network' to `null'!
        '';
      }
      { assertion = inst.zone != null -> (config.nixos.containers.zones != null && config.nixos.containers.zones ? ${inst.zone});
        message = ''
          No configuration found for zone `${inst.zone}'!
        '';
      }
    ]);

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
        ((flip mapAttrsToList cfg (name: config: if config.network == null then {} else {
          "20-${ifacePrefix "veth"}-${name}" = {
            matchConfig = mkMatchCfg "veth" name;
            address = config.network.v4.addrPool ++ config.network.v6.addrPool;
            networkConfig = mkNetworkCfg config.network.v4.nat;
          };
        }))
        ++ (flip mapAttrsToList config.nixos.containers.zones (name: zone: {
          "20-${ifacePrefix "zone"}-${name}" = {
            matchConfig = mkMatchCfg "zone" name;
            address = zone.v4.addrPool ++ zone.v6.addrPool;
            networkConfig = mkNetworkCfg zone.v4.nat;
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
