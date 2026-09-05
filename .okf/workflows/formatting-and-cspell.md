---
type: Reference
title: Formatting and cspell
description: The pre-commit suite declared in flake.nix, the generated config symlink that must not be edited, and how the spellchecker's dictionaries are assembled.
tags: [pre-commit, formatting, cspell, nix]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-05T22:06:36Z }
---

# Where the config lives

Hooks are declared in `flake.nix` under `checks.preCommitHooks`. The `.pre-commit-config.yaml` at the repo root is a **symlink into the nix store**, generated from that attrset and gitignored.

Never edit `.pre-commit-config.yaml` — the change is lost and cannot be committed. Edit `flake.nix` and re-enter the shell.

Run everything with `nix fmt`, which the flake's `formatter` output maps to `pre-commit run --all-files`.

# Hooks

| Group   | Hooks                                                                                                   |
| ------- | ------------------------------------------------------------------------------------------------------- |
| Files   | `trim-trailing-whitespace`, `end-of-file-fixer`, `fix-byte-order-marker`, `mixed-line-endings --fix=lf` |
| General | `prettier`                                                                                              |
| Nix     | `deadnix`, `nil`, `nixfmt`, `statix`                                                                    |
| Shell   | `shellcheck`, `shfmt`                                                                                   |
| CUE     | `cue-fmt`                                                                                               |
| Custom  | `sops-pre-commit` — see [secrets and SOPS](/workflows/secrets-sops.md)                                  |
| Git     | `conform` — see [commit conventions](/workflows/commit-conventions.md)                                  |

Prettier owns YAML formatting, which is most of this repository. `.editorconfig` fixes LF endings, a final newline, UTF-8, and 2-space indentation for YAML.

# cspell

The hook is not currently declared in `flake.nix`, but the configuration below is still checked in and still consumed when it is run by hand.

`.config/cspell.yaml` layers two dictionary sources:

1. A **git submodule**, `.config/cspell-dicts` → `github.com/Joker9944/cspell-dicts`, imported as `cspell-dicts/cspell.yaml` and shared with the author's other repos.
2. A repo-local `project` dictionary at `.config/dictionaries/project.txt`, with `addWords: true`.

Ignored paths: `*.sops.yaml`, `*.sops.yml`, `secret.yaml`, `*.json`, `flake.lock`, `/result`, `/.sops.yaml`, `.gitignore` and `/**/flux-system/*.yaml` (flux-generated).

For a one-off upstream identifier — an image owner, an env var, a chart author — the convention is an inline `# cSpell:ignore <word>` comment at the point of use rather than growing the project dictionary. Both forms are in use throughout `flake.nix`, `pkgs/` and the HelmReleases.

**Trap:** cspell fails to resolve its import if the submodule is not checked out. After a fresh clone, run `git submodule update --init`.
