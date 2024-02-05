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

      rev = "be886696affec833859fea4b44a560539cd52519";
      name = "VU-Server";
      mkPackage = { pkgs }:
        let

          src = pkgs.fetchFromGitHub {
            owner = "SasaKaranovic";
            repo = name;
            inherit rev;
            sha256 = "sha256-+CgGU25xM6/zse0ctaE3gxM7duUAKj9v0kJ1k5+zwrc=";
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
                  --t "$tmp"/ \
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
        };

        config = mkIf cfg.enable {
          systemd.services."VU-Server" = {
            wantedBy = [ "multi-user.target" ];
            script = ''
              set -x
              cp --recursive \
                --no-preserve=mode \
                --t "$STATE_DIRECTORY" / \
                ${pkg.vu-server}/bin/*
              ${pkg.python}/bin/python "$STATE_DIRECTORY"/server.py
            '';

            serviceConfig = {
              Restart = "on-failure";
              DynamicUser = "yes";
              RuntimeDirectory = "vu-server";
              RuntimeDirectoryMode = "0755";
              StateDirectory = "vu-server";
              StateDirectoryMode = "0755";
              CacheDirectory = "vu-server";
              CacheDirectoryMode = "0750";
            };
          };
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

