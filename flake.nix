{
  description = "Flake for VU-Server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      forAllSystems = function:
        nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ]
          (system:
            let
              pkgs = nixpkgs.legacyPackages.${system};
            in
            function { inherit pkgs system; });

      rev = "c3d2265aff2f9d81167256354e04c0a3eb0cf82d";
      name = "VU-Server";
      mkPackage = { pkgs }:
        let
          src = pkgs.fetchFromGitHub {
            owner = "hawkw";
            repo = name;
            inherit rev;
            sha256 = "QVSMnh9q6+efM8d2JziwfCm0jyquw5n2mji0eM4NZTM=";
          };
          python = pkgs.python3.withPackages
            (pythonPkgs: with pythonPkgs; [
              tornado
              numpy
              pillow
              requests
              pyyaml
              ruamel-yaml
              pyserial
            ]);

          serverPkg = pkgs.stdenv.mkDerivation
            {
              inherit src name;
              installPhase = ''
                mkdir -p $out/bin
                cp -r . $out/bin'';
              propagatedBuildInputs = [ python ];
            };
          runScript = pkgs.writeShellApplication
            {
              name = "vu-server-runner";

              runtimeInputs = [ serverPkg python ];

              text = ''
                set -x
                cp --recursive \
                  --no-preserve=mode \
                  --target-directory="$tmp"/ \
                  ${serverPkg}/bin/*
                  python "$tmp"/server.py
              '';
            };
        in
        {
          inherit python runScript;
          vu-server = serverPkg;
        };

      nixosModule = { config, lib, pkgs, ... }: with lib; let
        cfg = config.services.vu-server;
        pkg = mkPackage { inherit pkgs; };
      in
      {
        options.services.vu-server = {
          enable = mkEnableOption "VU-Server systemd service";
          server = mkOption
            {
              description = "Configuration for the VU-Server HTTP server.";
              default = { };
              type = with types; submodule {
                options = {
                  hostname = mkOption {
                    type = str;
                    default = "localhost";
                    example = "localhost";
                    description = "The server's hostname. Probably this should be localhost.";
                  };
                  port = mkOption
                    {
                      type = port;
                      default = 5340;
                      example = 5340;
                    };
                  communication_timeout = mkOption
                    {
                      type = int;
                      default = 5000;
                      example = 5000;
                      description = "The timeout for communication with the VU dials, in milliseconds.";
                    };
                  dial_update_period = mkOption
                    {
                      type = int;
                      default = 200;
                      example = 200;
                      description = "The period between dial updates, in milliseconds.";
                    };
                  master_key = mkOption
                    {
                      type = str;
                      default = "cTpAWYuRpA2zx75Yh961Cg";
                      example = "cTpAWYuRpA2zx75Yh961Cg";
                      description = "The master API key";
                    };
                };
              };
            };

        };

        config = mkIf cfg.enable (
          let
            configFile = pkgs.writeTextFile {
              name = "vu-server-config";
              text = builtins.toJSON {
                server = cfg.server;
                hardware = {
                  port = null;
                };
              };
            };
          in
          {

            systemd.services."VU-Server" = {
              wantedBy = [ "multi-user.target" ];
              description = "VU Dials server application";
              script = ''
                ${pkg.python}/bin/python server.py \
                  --config-path ${configFile} \
                  --state-path "$STATE_DIRECTORY" \
                  --log-path "$LOG_DIRECTORY" \
                  --lock-path "$RUNTIME_DIRECTORY" 
              '';

              serviceConfig = {
                Restart = "on-failure";
                # User = "vu-server";
                RuntimeDirectory = "vu-server";
                RuntimeDirectoryMode = "0755";
                StateDirectory = "vu-server";
                StateDirectoryMode = "0755";
                CacheDirectory = "vu-server";
                CacheDirectoryMode = "0750";
              };
            };

            services.udev.extraRules = ''
              KERNEL=="ttyUSB0", MODE="0666"
            '';
          }
        );
      };
    in
    {
      nixosModules.default = nixosModule;
      packages = forAllSystems ({ pkgs, ... }:
        let pkg = mkPackage { inherit pkgs; }; in {
          default = pkg.vu-server;
          vu-server = pkg.vu-server;
          runner = pkg.runScript;
        });
      apps = forAllSystems ({ system, ... }: {
        default = { type = "app"; program = "${self.packages.${system}.runner}/bin/vu-server-runner"; };
      });
      devShells = forAllSystems ({ pkgs, system }: {
        default = pkgs.mkShell {
          buildInputs = self.packages.${system}.vu-server.propagatedBuildInputs;
        };
      });
    };
}

