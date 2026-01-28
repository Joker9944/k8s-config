{
  description = "Kubernetes development flake";

  inputs = {
    # nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # third party packages
    talhelper = {
      url = "github:budimanjojo/talhelper/v3.0.30"; # cSpell:ignore budimanjojo talhelper
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # helpers
    flake-utils.url = "github:numtide/flake-utils/main"; # cSpell:ignore numtide
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
    in
    inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: lib.elem (lib.getName pkg) [ "steamcmd" ];
        };

        envParts = [
          {
            package = pkgs.kubectl;

            shellHook = ''
              source <(kubectl completion bash)
              alias garage="kubectl exec --tty --stdin --namespace garage garage-0 -c garage -- ./garage"
            '';
          }
          {
            package = pkgs.fluxcd;

            shellHook = ''
              source <(flux completion bash)
            '';
          }
          {
            package = pkgs.kubernetes-helm;

            shellHook = ''
              source <(helm completion bash)
            '';
          }
          {
            package = pkgs.talosctl;

            shellHook = ''
              export TALOSCONFIG="$PWD/clusters/nyx/talos/clusterconfig/talosconfig"
              source <(talosctl completion bash)
            '';
          }
          {
            package = inputs.talhelper.packages.${system}.default;

            shellHook = ''
              source <(talhelper completion bash)
            '';
          }
          {
            package = pkgs.sops;
          }
          {
            package = pkgs.age;
          }
          {
            package = pkgs.grafana-alloy;
          }
        ];
      in
      {
        packages = {
          # programs
          gomod-cap = pkgs.callPackage ./pkgs/gomod-cap.nix { flake = self; };
          gotify-slack-webhook = pkgs.callPackage ./pkgs/gotify-slack-webhook.nix { flake = self; };
          sops-pre-commit = pkgs.callPackage ./pkgs/sops-pre-commit.nix { flake = self; };

          # images
          abiotic-factor-server = pkgs.callPackage ./images/abiotic-factor-server { flake = self; };
          steamcmd = pkgs.callPackage ./images/steamcmd { flake = self; };
          base = pkgs.callPackage ./images/base.nix { flake = self; };
          gotify-custom = pkgs.callPackage ./images/gotify-custom.nix { flake = self; };
          jinja-cli = pkgs.callPackage ./images/jinja-cli.nix { flake = self; };
          postgresql-client = pkgs.callPackage ./images/postgresql-client.nix { flake = self; };
        };

        apps = lib.pipe envParts [
          (lib.map (
            {
              package,
              name ? package.meta.mainProgram,
              program ? lib.getExe package,
              meta ? package.meta,
              ...
            }:
            {
              inherit name;
              value = {
                type = "app";
                inherit program meta;
              };
            }
          ))
          lib.listToAttrs
        ];

        devShells = {
          default = self.devShells.${system}.k8s;

          k8s = pkgs.mkShell {
            name = "kubernetes-dev";

            packages = lib.map (
              {
                package,
                ...
              }:
              package
            ) envParts;

            shellHook =
              lib.pipe
                [
                  ''
                    PS1=$(echo "$PS1" | sed 's/\\u@\\h/\$name/g')
                  ''
                  (lib.pipe envParts [
                    (lib.filter (
                      {
                        shellHook ? null,
                        ...
                      }:
                      shellHook != null
                    ))
                    (lib.map ({ shellHook, ... }: shellHook))
                  ])
                ]
                [
                  lib.flatten
                  lib.concatLines
                ];
          };

          preCommitHooks =
            let
              inherit (self.checks.${system}.preCommitHooks) shellHook enabledPackages;
            in
            pkgs.mkShell {
              inherit shellHook;
              buildInputs = enabledPackages;
            };
        };

        checks = {
          default = self.checks.${system}.preCommitHooks;

          preCommitHooks = inputs.pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              # Files
              trim-trailing-whitespace.enable = true;
              end-of-file-fixer.enable = true;
              fix-byte-order-marker.enable = true;
              mixed-line-endings = {
                enable = true;
                args = [ "--fix=lf" ];
              };

              # General
              cspell = {
                enable = true;
                args = [ "--no-must-find-files" ];
              };
              prettier.enable = true;

              # Nix
              deadnix.enable = true;
              nil.enable = true;
              nixfmt.enable = true;
              statix.enable = true;

              # Shell
              shellcheck.enable = true;
              shfmt.enable = true;

              # Custom
              sops-pre-commit = {
                enable = true;

                name = "sops-pre-commit";
                entry = lib.getExe self.packages.${system}.sops-pre-commit;
                files = "((^|/)*.(ya?ml)$)";
              };
            };
          };
        };

        formatter =
          let
            inherit (self.checks.${system}.preCommitHooks.config) package configFile;
          in
          pkgs.writeShellScriptBin "pre-commit-hooks" ''
            ${package}/bin/pre-commit run --all-files --config ${configFile}
          '';
      }
    );
}
