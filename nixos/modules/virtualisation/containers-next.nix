{ pkgs, lib, config, ... }:

with lib;

let
  cfg = config.nixos.containers.instances;

  mkImage = name: config:
    { container = import "${config.nixpkgs}/nixos/lib/eval-config.nix" {
        system = "x86_64-linux";
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
        prefix = [ "nixos" "containers" name "config" ];
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
    networkConfig = {
      Private = true;
      Zone = "nixos";
    };
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
    systemd = {
      nspawn = mapAttrs (const mkContainer) images;
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
