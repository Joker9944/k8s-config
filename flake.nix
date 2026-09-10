{
  description = "Kubernetes development flake";

  inputs = {
    # nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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
        pkgs = import nixpkgs { inherit system; };

        envParts = [
          {
            package = pkgs.kubectl;

            shellHook = ''
              source <(kubectl completion bash)
              alias garage="kubectl exec --tty --stdin --namespace garage garage-0 -c garage -- ./garage"
            '';
          }
          {
            package = pkgs.kubectl-cnpg;

            shellHook = ''
              source <(kubectl cnpg completion bash)
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
            package = pkgs.sops;
          }
          {
            package = pkgs.cue;
          }
          {
            package = pkgs.age;
          }
          {
            package = pkgs.grafana-alloy;
          }
          {
            package = pkgs.mcp-grafana;

            shellHook = ''
              # .env is data, not shell: split on the first =, never evaluate it.
              # Anything that is not a bare identifier is a comment or junk.
              if [ -f .env ]; then
                while IFS='=' read -r key value; do
                  case "$key" in
                    "" | *[!A-Za-z0-9_]*) continue ;;
                  esac
                  export "$key=$value"
                done < .env
                unset key value
              fi
            '';
          }
        ];
        cueRender = pkgs.callPackage ./cue/render.nix { };
      in
      {
        packages = cueRender.perTier // {
          # programs
          gomod-cap = pkgs.callPackage ./pkgs/gomod-cap.nix { flake = self; };
          gotify-slack-webhook = pkgs.callPackage ./pkgs/gotify-slack-webhook.nix { flake = self; };
          sops-pre-commit = pkgs.callPackage ./pkgs/sops-pre-commit.nix { flake = self; };

          # cue render
          cue-render-bootstrap = cueRender.bootstrap;

          # images
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

          ci = pkgs.mkShell {
            name = "ci";

            packages = with pkgs; [
              skopeo
              jq
              cosign
              fluxcd
            ];
          };
        };

        checks = {
          cueVet = pkgs.stdenvNoCC.mkDerivation {
            name = "cue-vet";
            src = ./cue;
            nativeBuildInputs = [ pkgs.cue ];
            doCheck = true;
            checkPhase = "cue vet -c ./...";
            installPhase = "mkdir $out";
          };

          alloyValidate = pkgs.stdenvNoCC.mkDerivation {
            name = "alloy-validate";
            src = lib.fileset.toSource {
              root = ./cue;
              fileset = lib.fileset.fileFilter (f: f.hasExt "alloy") ./cue;
            };
            nativeBuildInputs = [ pkgs.grafana-alloy ];
            doCheck = true;
            checkPhase = ''
              mkdir alloy.d
              find . -name '*.alloy' -exec cp {} alloy.d/ \;
              test -n "$(ls -A alloy.d)" || { echo "no .alloy files found"; exit 1; }
              alloy validate alloy.d/
            '';
            installPhase = "mkdir $out";
          };

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
              prettier = {
                enable = true;
                excludes = [ "clusters/nyx/flux" ];
              };

              # Nix
              deadnix.enable = true;
              nixfmt.enable = true;
              statix.enable = true;

              # Shell
              shellcheck = {
                enable = true;
                excludes = [ ".envrc" ];
              };
              shfmt.enable = true;

              # CUE
              cue-fmt.enable = true;

              # Alloy
              alloy-fmt = {
                enable = true;

                name = "alloy-fmt";
                # alloy fmt takes at most one file; pre-commit passes the whole batch.
                entry = "${pkgs.writeShellScript "alloy-fmt" ''
                  for f in "$@"; do
                    ${lib.getExe pkgs.grafana-alloy} fmt -w "$f"
                  done
                ''}";
                files = "\\.alloy$";
              };

              # Custom
              sops-pre-commit = {
                enable = true;

                name = "sops-pre-commit";
                entry = lib.getExe self.packages.${system}.sops-pre-commit;
                files = "((^|/)*.(ya?ml)$)";
              };

              # Git
              conform.enable = true;
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
