---
type: Reference
title: Commit conventions
description: The conventional-commit policy conform enforces, the scope allowlist and the trees it maps to, and the commit sources that bypass the hook entirely.
tags: [git, conform, conventional-commits, pre-commit]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-05T22:06:36Z }
---

# Where it is enforced

`.conform.yaml` declares a single `commit` policy; the `conform` pre-commit hook runs it at the `commit-msg` stage, wired up in `flake.nix` alongside [the rest of the suite](/workflows/formatting-and-cspell.md).

It gates commits made **locally**, and nothing else. Renovate, the flake-update job and GitHub's squash-merge all write commit messages server-side, where no hook runs.

# The policy

All eleven conventional types are allowed (`build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, `test`), with `descriptionLength: 72`.

A scope is **optional** — `ci: pin actions/checkout` passes. The allowlist constrains scopes that are present, one per top-level tree in [the repo layout](/architecture/repo-layout.md):

| Scope         | Covers                                              |
| ------------- | --------------------------------------------------- |
| `cluster`     | `clusters/nyx/`                                     |
| `infra`       | `infrastructure/`                                   |
| `apps`        | `apps/`                                             |
| `components`  | `components/`                                       |
| `images`      | `images/`                                           |
| `pkgs`        | `pkgs/`                                             |
| `experiments` | `experiments/`                                      |
| `okf`         | `.okf/`                                             |
| `flake`       | `flake.nix`, `flake.lock`, the devShell, pre-commit |
| `deps`        | renovate and lockfile bumps                         |

Scopes are deliberately coarse: the workload name goes in the description, not the scope, so adding an app never edits `.conform.yaml`. `.config/` and repo-root files have no scope; commit them unscoped. Workflow changes are `ci:` — there is no `ci` scope, because that would read `ci(ci)`.

# Traps

- **`flake: update ./flake.lock` is not a valid message** — `flake` is a scope here, not a type. The job that emits it is `Joker9944/nix-config/.github/workflows/nix-flake-update.yaml@main`, [shared with nix-config](/workflows/images-and-ci.md), and it bypasses the hook. conform will not stop these landing on `main`; fixing them means editing the shared workflow.
- **Merge commits fail the format check.** `main` is linear because PRs are squash-merged, so this only surfaces on a local `git pull` that is not rebasing.
- Renovate descriptions routinely pass 72 characters once GitHub appends ` (#1234)`. Harmless while the policy is commit-msg-only; it would break the day it moves into CI.
