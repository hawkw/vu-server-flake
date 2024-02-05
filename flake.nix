{
  description = "Flake for VU-Server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      forAllSystems = function:
        nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ]
          (system: function nixpkgs.legacyPackages.${system});

      rev = "ee237b6d6842b43d927727743737e846b1415b53";
      name = "VU-Server";
      mkPackage = { pkgs }:
        let
          src = pkgs.fetchFromGitHub {
            owner = "SasaKaranovic";
            repo = name;
            inherit rev;
            sha256 = "wAg7iqArgX38VZDRoY6XCSWL0D8iVrXvDjdyyo+ADVw=";
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

        config = mkIf cfg.enable {
          environment.etc."vu-server/config.yaml".text = builtins.toJSON
            {
              server = cfg.server;
              hardware = {
                port = null;
              };
            };

          systemd.services."VU-Server" = {
            wantedBy = [ "multi-user.target" ];
            description = "VU Dials server application";
            script = ''
              set -x
              touch "$STATE_DIRECTORY"/vudials.db
              cd "$RUNTIME_DIRECTORY"
              cp --recursive \
                --no-preserve=mode \
                --symbolic-link \
                ${pkg.vu-server}/bin/* .
              ln -s "$STATE_DIRECTORY"/vudials.db .
              ln -s /etc/vu-server/config.yaml .
              ${pkg.python}/bin/python server.py
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
        };
      };
    in
    {
      nixosModules.default = nixosModule;
      packages = forAllSystems (pkgs:
        let pkg = mkPackage { inherit pkgs; }; in {
          default = pkg.vu-server;
          vu-server = pkg.vu-server;
          runner = pkg.runScript;
        });
      apps =
        nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ]
          (system: {
            default = { type = "app"; program = "${self.packages.${system}.runner}/bin/vu-server-runner"; };
          });
    };
}

