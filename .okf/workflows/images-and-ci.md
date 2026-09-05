---
type: Reference
title: Images, CI and dependency updates
description: How this repo's OCI images are built from Nix, published and signed, and how renovate is pointed at this repo's filename conventions.
tags: [nix, oci, github-actions, renovate, cosign]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-05T19:20:00Z }
---

# Images

Images under `images/` are `dockerTools.buildLayeredImage` derivations, not Dockerfile builds. All layer on `images/base.nix`, which supplies `fakeNss`, `usrBinEnv`, `caCertificates`, bash, coreutils, curl, procps, gnutar, gzip, findutils and tzdata, running as UID `65534` with `TZ=UTC`. Two of those are non-obvious: gnutar and gzip are present so `kubectl cp` works, curl and procps so health checks do.

The derivation's `tag` attribute is the **version of record**. The workflow reads `name:tag` back out of the built tarball's `manifest.json` rather than being told separately, so bumping an image means bumping its `tag`.

Published: `abiotic-factor-server`, `steamcmd`, `gotify-custom`, `jinja-cli`, `postgresql-client`. (`base` is built but not published — it only exists to be layered on.)

# Publishing

`.github/workflows/docker-publish.yaml` fires on pushes to `main` touching `flake.nix`, `flake.lock`, `images/**` or `pkgs/**`, one matrix job per image:

1. `nix build .#<attr>`
2. read `name:tag` from the tarball manifest, derive the tag list `latest`, major, minor, patch
3. `skopeo copy` the archive to `ghcr.io/joker9944/<name>` for the first tag, capturing its digest; remaining tags are copied registry-to-registry by that digest so all four point at one manifest
4. `cosign sign` every tag

Steps 3 and 4 run under `shell: nix develop .#ci --command bash {0}`, which is the only consumer of that shell.

# pkgs/

Non-image derivations:

- **`gotify-slack-webhook`** — a Go _plugin_ (`-buildmode=plugin`, `CGO_ENABLED=1`). Go plugins must be built against the exact dependency versions of their host, so the derivation fetches the upstream `gotify-server` `go.mod`, runs `gomod-cap` to cap the plugin's requirements to it, syncs the Go and toolchain versions, and only then builds. It lands in `$out/lib/gotify/plugins/`, baked into the [`gotify-custom` image](/platform/observability.md).
- **`gomod-cap`** — the capping utility, built from `gotify/plugin-api`.
- **`sops-pre-commit`** — see [secrets and SOPS](/workflows/secrets-sops.md).

# Other workflows

`nix-flake-check.yaml` (on PRs) and `nix-flake-update.yaml` both **reuse workflows from `Joker9944/nix-config`**, as does the `nix-setup` composite action used by the publish job. Changes to shared CI happen in that repository, not this one.

# Renovate

`.github/renovate.json5`, weekend schedule, dependency dashboard enabled, assigned to `Joker9944`.

| Update kind               | Behavior                           |
| ------------------------- | ---------------------------------- |
| minor, patch, pin, digest | `automerge`                        |
| major                     | dashboard approval, no `automerge` |
| docker `talos`, `kubelet` | dashboard approval, no `automerge` |

The stock flux and helm-values managers are re-pointed at this repo's filenames (`helm-release.yaml`, `kustomization.yaml`, `{helm,git,oci}-repository.yaml`) — a file named otherwise is invisible to renovate.

A custom regex manager reads `# renovate: datasource=… depName=… packageName=…` comments immediately above a version key in `talconfig.yaml`, `docker-publish.yaml` and `helm-release.yaml`. That comment is the only thing keeping the [Talos and Kubernetes versions](/platform/talos-nyx.md) and the [Traefik plugin versions](/platform/networking-and-ingress.md) updated.
