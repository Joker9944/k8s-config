---
type: Decision
title: Replace kustomize with CUE
description: CUE replaces kustomize as the composition layer; Flux, HelmReleases and the bjw-s app-template chart stay, and rendered manifests reach the cluster as per-tier OCI artifacts.
tags: [cue, kustomize, gitops, flux, decision]
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-07T22:00:00Z }
stale_after: 2027-03-05
sources:
  - id: fluxcd-cues
    resource: https://github.com/fluxcd/cues
    title: fluxcd/cues
    last_modified: 2023-08-02
---

# Decision

CUE replaces kustomize as the composition layer. Flux, the `HelmRelease` model and
the bjw-s `app-template` chart are unchanged. CUE renders plain YAML in CI, which
is published as one signed OCI artifact per tier and consumed by `OCIRepository`.

Taken: the kustomize tree is deleted and the module lives at `cue/`.

# The problem is kustomize, not YAML

Of 19313 tracked YAML lines, 10417 are flux-generated and 1077 are ciphertext.
Of the 7531 hand-written lines that remain, 3275 (43%) are `spec.values` blobs
defined by the chart, not by Kubernetes — no typed DSL improves those.

What hurts is the ~2400 lines of scaffolding that exist only because kustomize
has no variables or functions: the `PLACEHOLDER`/`replacements` machinery, the
per-app `nameReference` configs, 28 four-line namespace files. Those are what
CUE deletes. See [the CUE layout](/architecture/cue-layout.md) for what each replaced.

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
need no annotation because the `repository`/`tag` pair is self-describing. Chart
versions need one comment each, which is 18 foreign charts plus the
`_appTemplateVersion` default covering every app-template release at once. CUE
comments are `//` — `#` is the definition sigil, so `# renovate:` is impossible.
See [images, CI and dependency updates](/workflows/images-and-ci.md).

# What it costs

- `git blame` on a manifest no longer explains it; inspection is `cue export`
  locally or `flux pull artifact`.
- CI enters the deploy path. A failed render means no new artifact; running
  workloads are unaffected, but updates stall.
- Every `secretGenerator` secret converts to a manifest, which has to supply the
  `metadata.namespace` kustomize used to inject; the failure is not loud.
- CUE's own traps, catalogued in the proof-of-concept: self-reference cycles,
  definitions closing recursively, and `x != _|_` not testing whether an optional field is
  set.

# How it was checked

A fidelity gate rendered both trees, decrypted each the way kustomize-controller
does, and compared them resource by resource. It ended green across all 32
bundles and 302 resources, with 35 disagreements named in an allowlist and the
rest byte-identical. A green gate never meant the trees agreed — it meant every
disagreement carried a reason, and the gate failed just as hard on an entry whose
resource turned out identical, so an exemption could not outlive what it excused.
Everything it excused was a manifest CUE renders per the fleet's own conventions
while kustomize still rendered the divergence.

The gate died with `apps/base/`, as designed. `cue/verify.sh` outlives it and
covers the constraint and API-surface checks.

[^fluxcd-cues]: fluxcd/cues
