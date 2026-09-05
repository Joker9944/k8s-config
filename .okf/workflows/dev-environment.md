---
type: Reference
title: Development environment
description: What the Nix flake provides — the envParts list that drives both the dev shell and the runnable apps, plus the CI and pre-commit shells.
tags: [nix, flake, dev-shell, tooling]
resource: flake.nix
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-05T19:20:00Z }
---

# The dev shell

`nix develop` (or direnv) enters `devShells.k8s`, which is also `devShells.default`.

Tools are declared **once** in the `envParts` list — a package plus an optional `shellHook` — and that one list is consumed twice: `devShells.k8s` takes the packages and concatenates the hooks, while `apps` maps each entry to `nix run .#<mainProgram>`. Adding a tool means adding one attrset.

| Package                                    | Hook                                                                                     |
| ------------------------------------------ | ---------------------------------------------------------------------------------------- |
| `kubectl`                                  | bash completion; `garage` alias running the CLI inside the `garage-0` pod                |
| `fluxcd`                                   | bash completion                                                                          |
| `kubernetes-helm`                          | bash completion                                                                          |
| `talosctl`                                 | bash completion; exports `TALOSCONFIG=$PWD/clusters/nyx/talos/clusterconfig/talosconfig` |
| `talhelper` (flake input, pinned `v3.1.3`) | bash completion                                                                          |
| `sops`, `age`                              | —                                                                                        |
| `grafana-alloy`                            | —                                                                                        |

`talhelper` is a pinned flake input rather than a nixpkgs package, so its version moves with `flake.lock` and the `nix-flake-update` workflow, not with the nixpkgs channel.

# Other shells

- `devShells.preCommitHooks` — derived from `checks.preCommitHooks`, see [formatting and cspell](/workflows/formatting-and-cspell.md).
- `devShells.ci` — `skopeo`, `jq`, `cosign`. Entered explicitly by the publish workflow as `nix develop .#ci`; see [images and CI](/workflows/images-and-ci.md).

# Flake outputs

- `packages` — three programs (`gomod-cap`, `gotify-slack-webhook`, `sops-pre-commit`) and six OCI images.
- `apps` — generated from `envParts`.
- `checks.default` = `checks.preCommitHooks`.
- `formatter` — a wrapper running `pre-commit run --all-files` against the generated config, so `nix fmt` runs the whole hook suite rather than a formatter.

`config.allowUnfreePredicate` permits exactly one package, `steamcmd`, needed by the abiotic-factor server image.
