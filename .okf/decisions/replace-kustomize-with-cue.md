---
type: Decision
title: Replace kustomize with CUE
description: CUE replaces kustomize as the composition layer; Flux, HelmReleases and the bjw-s app-template chart stay, and rendered manifests reach the cluster as per-tier OCI artifacts.
tags: [cue, kustomize, gitops, flux, decision]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-07T12:00:00Z }
stale_after: 2027-03-05
sources:
  - id: poc
    resource: ../../experiments/cue/README.md
    title: CUE proof-of-concept (jellyfin and servarr)
  - id: fluxcd-cues
    resource: https://github.com/fluxcd/cues
    title: fluxcd/cues
    last_modified: 2023-08-02
---

# Decision

CUE replaces kustomize as the composition layer. Flux, the `HelmRelease` model and
the bjw-s `app-template` chart are unchanged. CUE renders plain YAML in CI, which
is published as one signed OCI artifact per tier and consumed by `OCIRepository`.

# The problem is kustomize, not YAML

Of 19313 tracked YAML lines, 10417 are flux-generated and 1077 are ciphertext.
Of the 7531 hand-written lines that remain, 3275 (43%) are `spec.values` blobs
defined by the chart, not by Kubernetes — no typed DSL improves those.

What hurts is the ~2400 lines of scaffolding that exist only because kustomize
has no variables or functions: the `PLACEHOLDER`/`replacements` machinery, the
per-app `nameReference` configs, 28 four-line namespace files. Those are what
CUE deletes. See [kustomize components](/architecture/kustomize-components.md).

# Rejected

| Option                         | Why not                                                                                                                                                                           |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Nix (kubenix or plain)         | Its edge was one toolchain with the NixOS host migration, and merging into `nix-config` is only a possibility. It cannot express the constraint layer, which is the actual prize. |
| Timoni                         | No `app-template` equivalent. Adopting it means reimplementing that chart and maintaining it, across every workload.                                                              |
| kpt                            | Another textual-substitution engine. Leaving kustomize means leaving the category.                                                                                                |
| Commit rendered YAML to `main` | Renovate would merge a bump whose rendered output is stale, so CI must push back into the PR before automerge. That puts a write-back loop in the busiest path in the repo.       |
| Render to a `deploy` branch    | Viable runner-up, and the only option preserving `git blame` on manifests. Rejected for lacking signature verification, not on mechanics.                                         |

# How it works

**Constraints are hard; exceptions are named.** `#Hardened` pins the security
context and requires a digest-pinned image. A workload that genuinely cannot
comply uses a separate definition — `#HardenedWritableRoot` — so exceptions are
easy to find with `grep`, and each is a deliberate choice. Softening a constraint into an
overridable default is not the escape hatch.

**Flux resources are typed from Flux's own Go API.** `cue get go` against
helm-controller, kustomize-controller and source-controller yields CUE
definitions vendored under `cue.mod/gen/`. Versions are read from
`clusters/nyx/flux/flux-system/gotk-components.yaml`, so they track the running
controllers and a Flux upgrade produces a reviewable diff. `fluxcd/cues` rotted
precisely because its vendored definitions were frozen at
`helm.toolkit.fluxcd.io/v2beta1` with nothing tying them to reality.[^fluxcd-cues]
Enum and duration constraints are not carried across, because kubebuilder markers
are comments rather than Go types.

**Delivery is one OCI artifact per tier.** A single artifact would let one
evaluation error block updates to every workload; per-tier keeps the blast radius
where [the Flux topology](/architecture/flux-topology.md) already puts it. The
artifact is cosign-signed by the same machinery that signs
[the repo's images](/workflows/images-and-ci.md), and verified in-cluster via
`OCIRepository.spec.verify` — the cluster currently verifies nothing.

**Secrets are passthrough files that CUE never reads.** Every secret takes the
`manifests/secret.yaml` shape already used by most of them: a real Secret
manifest with only `data`/`stringData` encrypted. `secretGenerator` is dropped,
which also removes the generated-name hash. Each bundle declares its files in a
`secretFiles` list; the render step copies them verbatim beside the generated
manifests. They are deliberately **not** embedded — embedding reproduces the
shape `forbid_secrets` rejects. Naming matters: a converted file must match the
`secret.yaml` rule, not the whole-file `.sops.yaml` one. See
[secrets and SOPS](/workflows/secrets-sops.md).

**Layout** is a package per workload, collected by a package per tier, so the
tier is at once the CUE package, the unit of rendering and the OCI artifact.
`base/` and `nyx/` collapse into one file per tier, and `components/` has no
successor tree. See [the CUE layout](/architecture/cue-layout.md).

**Renovate** keeps working through regex managers over `.cue`: container images
need no annotation because the `repository`/`tag` pair is self-describing, and
chart versions need one annotation total, since the version is a `#Release`
default rather than a field on 19 HelmReleases. CUE comments are `//` — `#` is
the definition sigil, so `# renovate:` is impossible.

# What it costs

- `git blame` on a manifest no longer explains it; inspection is `cue export`
  locally or `flux pull artifact`.
- CI enters the deploy path. A failed render means no new artifact; running
  workloads are unaffected, but updates stall.
- Nine secrets must convert from the `secretGenerator` shape, which has no CUE
  successor, and every converted file needs the `metadata.namespace` and
  `type: Opaque` kustomize used to supply.
- CUE's own traps, catalogued in the proof-of-concept: self-reference cycles,
  definitions closing recursively, and `x != _|_` not testing whether an optional field is
  set.

# Evidence

All 32 bundles are ported in `experiments/cue/`, which carries its own
README.[^poc] `gate.sh` renders both sides and compares resource by resource,
decrypting each the way kustomize-controller does. It reads the bundle registry
out of CUE, so porting a workload enrols it in the gate rather than needing the
script edited. `verify.sh` covers the constraint and API-surface checks. Both are
migration scaffolding and die with `apps/base/`.

A green gate does not mean the two trees agree. It means every disagreement is
named in `allowlist.txt` with a reason, and the gate fails just as hard on an
entry whose resource turns out identical — so an exemption cannot outlive what it
excuses. Everything listed today is a manifest CUE renders per the fleet's own
conventions while kustomize still renders the divergence.

[^poc]: CUE proof-of-concept (jellyfin and servarr)

[^fluxcd-cues]: fluxcd/cues
