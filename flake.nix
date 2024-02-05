{
  description = "Flake for VU-Server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        gitRev = "be886696affec833859fea4b44a560539cd52519";
        src = pkgs.fetchFromGitHub {
          owner = "SasaKaranovic";
          repo = "VU-Server";
          rev = gitRev;
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

        pythonPkg = pkgs.stdenv.mkDerivation
          {
            name = "VU-Server";
            inherit src;
            installPhase = ''
              mkdir -p $out/bin
              cp -r . $out/bin'';
            propagatedBuildInputs = [ python ];
          };
        runScript = pkgs.writeShellApplication
          {
            name = "vu-server-runner";

            runtimeInputs = [ pythonPkg python ];

            text = ''
              set -x
              cp --recursive \
                --no-preserve=mode \
                --t "$tmp"/ \
                ${pythonPkg}/bin/*
              ${python}/bin/python "$tmp"/server.py
            '';
          };
        nixosModule = { config, lib, pkgs, ... }: with lib; let
          cfg = config.services.vu-server;
          pkg = self.${system}.packages.vu-server;
        in
        {
          options.services.vu-server = {
            enable = mkEnableOption "VU-Server systemd service";
          };

          config = mkIf cfg.enable {
            wantedBy = [ "multi-user.target" ];
            script = ''
              set -x
              cp --recursive \
                --no-preserve=mode \
                --t . / \
                ${pkg}/bin/*
              ${python}/bin/python "$tmp"/server.py
            '';

            serviceConfig = {
              Restart = "on-failure";
              DynamicUser = "yes";
              RuntimeDirectory = "vu-server";
              RuntimeDirectoryMode = "0755";
              StateDirectory = "vu-server";
              StateDirectoryMode = "0700";
              CacheDirectory = "vu-server";
              CacheDirectoryMode = "0750";
            };
          };

        };
      in
      {
        packages =
          {
            default = self.packages.${system}.vu-server;
            vu-server = pythonPkg;
            runner = runScript;
          };
        nixosModules.default = nixosModule;
        apps.default = {
          type = "app";
          program = "${self.packages.${system}.runner}/bin/vu-server-runner";
        };
      });
}


