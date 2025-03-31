{
  description = "Kubernetes development flake";

  inputs = {
    # nix pkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    # nix helpers
    flake-parts.url = "github:hercules-ci/flake-parts";
    # external pkgs
    talhelper = {
      url = "github:budimanjojo/talhelper/v3.0.19";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
      perSystem = {
        config,
        self',
        inputs',
        pkgs,
        pkgs-unstable,
        system,
        ...
      }: {
        _module.args.pkgs-unstable = import inputs.nixpkgs-unstable {
          inherit system;
          overlays = [inputs.talhelper.overlays.default];
        };

        devShells = {
          default = pkgs.mkShell {
            name = "kubernetes-dev";

            packages = with pkgs; [
              kubectl
              fluxcd
              kubernetes-helm
              pkgs-unstable.talosctl
              pkgs-unstable.talhelper

              sops
              age
            ];

            shellHook = ''
              # Autocompletion
              source <(kubectl completion bash)
              source <(flux completion bash)
              source <(helm completion bash)
              source <(talosctl completion bash)
              source <(talhelper completion bash)
            '';
          };

          flake = pkgs.mkShell {
            name = "flake-dev";

            packages = with pkgs; [alejandra];
          };
        };

        formatter = pkgs.alejandra;
      };
    };
}
