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

      rev = "3c724450e611f31c23660ae763cb80868c6a4285";
      name = "VU-Server";
      mkPackage = { pkgs }:
        let
          src = pkgs.fetchFromGitHub {
            owner = "hawkw";
            repo = name;
            inherit rev;
            sha256 = "wgfiqaXKPDQ7SuyUzmRmqBqlRDsIuIhmnihsd6KzuCY=";
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
                STATE=''${XDG_STATE_HOME:-$HOME/.local/state}
                python ${serverPkg}/bin/server.py \
                  --state-path "$STATE/vu-server" \
                  --log-path "$STATE/log" \
                  --lock-path "''${XDG_RUNTIME_DIR:-/tmp}" \
                  "$@"
              '';
            };
        in
        {
          inherit python runScript;
          vu-server = serverPkg;
        };
    in
    {
      nixosModules.default = { config, lib, pkgs, ... }: with lib; let
        cfg = config.services.vu-dials.server;
        pkg = mkPackage { inherit pkgs; };
        defaultPort = 5340;
        defaultTimeoutSecs = 30;
        defaultPeriodMs = 200;
        defaultMasterKey = "cTpAWYuRpA2zx75Yh961Cg";
        dirname = "vu-server";

      in
      {
        options.services.vu-dials.server = {
          enable = mkEnableOption "Streacom VU-1 Dials HTTP server";
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
                      default = defaultPort;
                      example = defaultPort;
                    };
                  communication_timeout = mkOption
                    {
                      type = int;
                      default = defaultTimeoutSecs;
                      example = defaultTimeoutSecs;
                      description = "The timeout for communication with the VU dials, in seconds.";
                    };
                  dial_update_period = mkOption
                    {
                      type = int;
                      default = defaultPeriodMs;
                      example = defaultPeriodMs;
                      description = "The period between dial updates, in milliseconds.";
                    };
                  master_key = mkOption
                    {
                      type = str;
                      default = defaultMasterKey;
                      example = defaultMasterKey;
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
              description = "Streacom VU-1 dials HTTP server";
              script = ''
                set -x
                ${pkg.python}/bin/python ${pkg.vu-server}/bin/server.py \
                  --config-path ${configFile} \
                  --state-path "$STATE_DIRECTORY" \
                  --log-path "/var/log/${dirname}/" \
                  --lock-path "$RUNTIME_DIRECTORY"
              '';

              serviceConfig = {
                Restart = "on-failure";
                DynamicUser = "yes";
                RuntimeDirectory = dirname;
                RuntimeDirectoryMode = "0755";
                StateDirectory = dirname;
                StateDirectoryMode = "0755";
                CacheDirectory = dirname;
                CacheDirectoryMode = "0750";
              };
            };

            services.udev.extraRules = ''
              KERNEL=="ttyUSB0", MODE="0666"
            '';
          }
        );
      };

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

