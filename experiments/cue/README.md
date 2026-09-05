# CUE proof-of-concept

An evaluation of replacing kustomize with CUE as the composition layer, keeping
Flux, HelmReleases and the bjw-s `app-template` chart unchanged.

Two apps are ported. **jellyfin** exercises the single-release cases: a volsync
source/destination pair, NFS and PVC and emptyDir persistence, a GPU toleration,
a LoadBalancer service, an ingress with a namespace-qualified middleware, and
SOPS values. **servarr** exercises composition: six releases in one namespace, a
shared Postgres cluster, and four near-identical `*arr` apps.

Nothing here is deployed. `apps/base/*` remains the source of truth.

## Running it

```sh
./verify.sh
```

Renders `apps/base/jellyfin` with both kustomize and CUE, compares them with keys
sorted, then checks that four house-style violations are rejected. Exits non-zero
if any constraint stops holding. Tools come unpinned from the nixpkgs registry;
if CUE is adopted, `cue` moves into `envParts` in `flake.nix`.

## Files

| File           | Contents                                                                                                |
| -------------- | ------------------------------------------------------------------------------------------------------- |
| `schema.cue`   | `#Digest`, `#Hardened`, `#Chain`, `#Middlewares`, `#VolsyncRestic` — the constraint and generator layer |
| `app.cue`      | `#App` — namespace, HelmRepository, HelmRelease scaffolding, ingress annotations                        |
| `jellyfin.cue` | The app itself. The only file a person edits per workload.                                              |
| `data.cue`     | The injection point for SOPS ciphertext, which never passes through CUE evaluation                      |
| `render.cue`   | `yaml.MarshalStream` over the resource list                                                             |

## Results

**Fidelity.** servarr renders **byte-identical across all 1942 lines**, 19
resources, Secrets excluded. jellyfin differs by 4 lines of 382 — the
secretGenerator hash suffix, in the Secret's name and in `valuesFrom`. Document
order is normalized on both sides; it is not meaningful to Flux.

**servarr broke the first abstraction, which was the point.** `#App` assumed one
release per namespace. Six releases sharing a namespace, a HelmRepository and one
middleware set forced the split into `#Release` and `#Bundle` — jellyfin's diff
staying at 4 lines was the regression test for that refactor.

**The four `*arr` apps collapse.** 979 lines of near-duplicate HelmRelease YAML
become a 176-line `#Arr` and **11 lines per app**. Their differences turn out to
be eight parameters, and writing them down exposed two inconsistencies that YAML
hid: prowlarr emits `COMPlus_EnableDiagnostics` as an unquoted `0` where the
others use `"0"`, and sonarr-standard sets `DATABASE_ROLE` while sonarr-anime
does not.

**The CNPG roles are derived.** `spec.managed.roles` is generated from the app
list rather than hand-maintained, so adding an `*arr` cannot forget its Postgres
role — today those two lists are related only by convention.

**Constraints.** Four violations are rejected at build time: an image tag without
a digest, `readOnlyRootFilesystem: false`, an ingress naming another namespace's
middleware, and an undefined middleware chain. The third is the failure mode that
`apps/base/*` is currently exposed to — `#App` computes the annotation from
`namespace` and `chain`, so an app cannot write it.

**Typed Flux resources.** `cue.mod/gen/` holds CUE definitions generated from
helm-controller, kustomize-controller and source-controller's own Go API
packages, so `#App` emits a `#HelmRelease` rather than an untyped struct.
`generate.sh` reads the controller versions out of
`clusters/nyx/flux/flux-system/gotk-components.yaml`, which makes the
definitions track what nyx actually runs and turns a Flux upgrade into a
reviewable diff.

What this buys is the opposite of what it first appears. `#App` is a definition,
so CUE already closed everything inside it — a misspelled field was rejected
before. What typing adds is the **whole Flux API surface without hand-declaring
it**: `spec.timeout`, `spec.install.crds` (which garage needs) and
`spec.driftDetection` are accepted, while `spec.chartt` is still rejected.
Without the generated definitions, `#App` would have to enumerate every Flux
field any workload might ever use.

Two limits. Enum values are **not** validated — `install.crds: "Nonsense"` is
accepted, because kubebuilder enum markers are comments and `cue get go` reads
Go types. Neither are durations: `metav1.Duration` generates to the top type, so
`timeout: "banana"` passes. `spec.values` stays untyped, as it must.

**Size.**

|                          | YAML today            | CUE |
| ------------------------ | --------------------- | --- |
| jellyfin                 | 243                   | 114 |
| servarr (excluding SOPS) | 1972                  | 442 |
| shared layer             | ~1300 across the repo | 235 |

## Open questions

**The generator hash (likely a non-issue).** kustomize renames the Secret on
every content change, which is what forces a Helm upgrade. CUE emits a stable
name. The HelmRelease v2 CRD carries `lastAttemptedConfigDigest`, which is
helm-controller digesting the resolved config including `valuesFrom` — so the
upgrade should still happen. Worth confirming empirically once.

Related: committing rendered manifests is not viable, because the generated
Secret holds base64-of-ciphertext with no file-level `sops:` block and
`forbid_secrets` rejects it. The resolution is to drop `secretGenerator` and
hand-write a SOPS `secret.yaml`, which also makes the Secret name stable by
construction.

**Renovate.** The built-in flux and helm-values managers key off
`helm-release.yaml` and `kustomization.yaml` and would go blind. Regex managers
for `.cue` were validated for both container images and chart versions, and a
simulated bump round-tripped to one changed output line. Two costs: every chart
version needs an annotation comment (~40 of them), and **`#` is CUE's definition
sigil, so `# renovate:` comments are impossible** — the annotation must be `//`.

**Ergonomics.** Four things cost time and would cost it again:

- `version: version` is a cycle, not a copy. Quoted labels do not bind
  identifiers, so `"version": version` is the idiom. This is the common trap.
- List concatenation with `+` is superseded by `list.Concat`.
- A `let` binding and a field of the same name collide in one scope.
- Errors point at the definition site rather than the offending value: the
  constraint violations above report `app.cue`, not the file that broke them.
- `x != _|_` does not test whether an optional field is set — referencing an
  absent optional field is itself an error. The working idiom is a sentinel
  default (`host: string | *""`). This only surfaced with servarr, because
  jellyfin always had an ingress.
- Definitions close recursively, so a nested struct meant to be extended needs an
  explicit `...`.

## Changes this required outside the experiment

`.config/cspell.yaml` gained `cue.mod/gen/**` in `ignorePaths`, and an override
mapping `**/*.cue` to the `yaml` languageId. cspell has no languageId for `.cue`, so none of the per-language
dictionaries from the `cspell-dicts` submodule applied and ordinary Kubernetes
vocabulary was flagged. Three words were added to the project dictionary.

## A policy question this surfaced

`#Hardened` pins `readOnlyRootFilesystem: true`, and flaresolverr genuinely
cannot run that way. CUE refused to render it, which is the constraint working.

The fix was **not** to soften `#Hardened` into an overridable default — that
would silently permit the same thing everywhere. Instead there is a second,
named definition, `#HardenedWritableRoot`. Exceptions are now easy to find with `grep`, and each
one is a deliberate decision.

## Not yet evaluated

The delivery mechanism. CUE has to render before Flux sees it; `OCIRepository`
with cosign verification is supported by the running Flux and is the obvious
path, but no pipeline exists here.

<!-- cSpell:ignore chartt -->
