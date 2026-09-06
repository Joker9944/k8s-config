# CUE proof-of-concept

An evaluation of replacing kustomize with CUE as the composition layer, keeping
Flux, HelmReleases and the bjw-s `app-template` chart unchanged.

All 32 bundles are ported — twelve in `apps/`, sixteen in
`infrastructure/base/` and the four `infrastructure/nyx/config/` cluster
singletons, across eight tiers. Between them they exercise every shape
the tree has: single and multiple releases per namespace, the bjw-s app-template
and twelve foreign charts, charts from a `GitRepository` by branch and by tag,
nested Flux `Kustomization`s, volsync pairs, generated ConfigMaps, CNPG
clusters, LoadBalancer services, namespace-local middlewares and certificates,
Pod Security labels, a two-tier private CA, and SOPS secrets in both the
whole-file and manifest shapes. Only the level-3 sync manifests are left.

Nothing here is deployed. `apps/base/*` remains the source of truth. The
conclusions drawn from this are recorded in `.okf/decisions/replace-kustomize-with-cue.md`,
and the tree follows the layout in `.okf/architecture/cue-layout.md`: a package
per workload, a collector package per tier.

The tree is **self-contained**. It reads nothing from `apps/base/`, because a
replacement that sources from what it replaces stops working the moment the
original is deleted. Its plaintext files and its SOPS secrets are its own.

## Running it

```sh
./gate.sh    # fidelity: does CUE still render what kustomize renders?
./verify.sh  # constraints: do the house-style rules still hold?
```

`gate.sh` is the migration's quality gate. It finds tiers on disk and bundles in
each tier's own `gateMeta`, so porting a workload enrols it automatically, and
compares resource by resource — a missing resource fails as loudly as a wrong
field. It needs the age key. It dies with `apps/base/`; `verify.sh` outlives it.

Tools come unpinned from the nixpkgs registry; if CUE is adopted, `cue` moves
into `envParts` in `flake.nix`.

## Files

| Path                       | Contents                                                                                                     |
| -------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `schema/schema.cue`        | `#Digest`, `#Hardened`, `#Chain`, `#Middlewares`, `#VolsyncRestic`, `#ConfigMapFiles`, `#NamespaceCert`      |
| `schema/bundle.cue`        | `#Release`, `#AppRelease`, `#Bundle`, `#ConfigBundle`, `#Tier` — scaffolding, ingress annotations, rendering |
| `<tree>/<tier>/<tier>.cue` | The tier collector. Naming a workload here is what deploys it.                                               |
| `<tree>/<tier>/*/`         | One package per workload, with its own `files/`, `secrets/` and notes.                                       |
| `gate.sh` / `gate.py`      | Fidelity gate: renders both sides, decrypts both, normalizes, compares                                       |
| `allowlist.txt`            | Resources permitted to differ. Currently empty.                                                              |
| `verify.sh`                | Constraint checks                                                                                            |
| `generate.sh`              | Regenerates `cue.mod/gen/` from the Flux versions nyx runs                                                   |

## Results

**Fidelity.** Every resource matches, with nothing excluded: **292 of 292**
across the 32 bundles, including all 43 SOPS Secrets across 22 files. The
allowlist is empty.

**Both sides are decrypted before comparison**, the way kustomize-controller
decrypts a source before building it. This became necessary once the secrets
moved into the CUE tree: re-encrypting identical plaintext produces different
ciphertext, so comparing ciphertext would only ever prove that no file had been
touched. Comparing plaintext proves the migration preserved the actual values.
The gate therefore needs the age key, holds decrypted material in memory and in
one mode-0700 temporary tree it shreds on exit, and writes nothing decrypted
into the repository.

Four differences are normalized rather than exempted, because none is semantic:
document and key order, which Flux does not read; kustomize's generator name
suffix, which is only stripped where CUE emits the bare name at the same kind;
whitespace inside base64 `data`, because kustomize writes Secret values as a
wrapped block scalar and the line breaks land in the string; and `stringData`
against `data`, which Kubernetes defines as the same Secret. Anything that
decodes differently still fails.

**A closed definition is the wrong element type, twice over.** `#Bundle.releases`
was `[...#Release]` and `#Tier.bundles` was `[string]: #Bundle`, and each
rejected the first derived definition that came along — `#AppRelease`, then
`#ConfigBundle`. Both now name the structural shape their consumer actually
reads, which is the more honest contract anyway: `#Bundle` only ever touches
`r.out`, and `#Tier` only `out`, `source` and `secretFiles`.

**`infrastructure/` cost four schema fields and no restructuring.** The
`#Release`/`#AppRelease` split held: 13 of the 16 run a foreign chart and none
needed a new definition to place its ingress. What it did need was `crds` (the
`install`/`upgrade` block ten releases carry byte-identically), `tag` and
`ignore` on `#GitRepo`, and `#NamespaceCert` — which is a net deletion, because
it retires both `namespace-cert` components and the kustomize#5953 workaround
that duplicated them.

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
`apps/base/*` is currently exposed to — `#Release` computes the annotation from
`namespace` and `chain`, so a release cannot write it.

**Typed Flux resources.** `cue.mod/gen/` holds CUE definitions generated from
helm-controller, kustomize-controller and source-controller's own Go API
packages, so `#Release` emits a `#HelmRelease` rather than an untyped struct.
`generate.sh` reads the controller versions out of
`clusters/nyx/flux/flux-system/gotk-components.yaml`, which makes the
definitions track what nyx actually runs and turns a Flux upgrade into a
reviewable diff.

What this buys is the opposite of what it first appears. `#Release` is a
definition, so CUE already closed everything inside it — a misspelled field was rejected
before. What typing adds is the **whole Flux API surface without hand-declaring
it**: `spec.timeout`, `spec.install.crds` (which garage needs) and
`spec.driftDetection` are accepted, while `spec.chartt` is still rejected.
Without the generated definitions, `#Release` would have to enumerate every Flux
field any workload might ever use.

Two limits. Enum values are **not** validated — `install.crds: "Nonsense"` is
accepted, because kubebuilder enum markers are comments and `cue get go` reads
Go types. Neither are durations: `metav1.Duration` generates to the top type, so
`timeout: "banana"` passes. `spec.values` stays untyped, as it must.

**Size.**

|                                           | YAML today | CUE  |
| ----------------------------------------- | ---------- | ---- |
| all of `apps/` (excluding SOPS)           | 4394       | 1860 |
| all of `infrastructure/base` (excl. SOPS) | 1935       | 1343 |
| `infrastructure/nyx/config` (excl. SOPS)  | 259        | 251  |
| shared layer                              | ~1600      | 521  |

The workloads that collapse hardest are the ones that were most repetitive:
servarr 1972 → 459, blocky 233 → 180, jellyfin 243 → 122. opencloud barely moves
(66 → 67) because its values are all chart-specific and there was nothing to
share, and `nyx/config` barely moves for the same reason — one-off cluster
resources with no second instance to factor against. Line count is the wrong
measure there; what those bundles buy is that the CA chain and the storage
classes are now referenced by name rather than retyped.

## Open questions

**The generator hash (likely a non-issue).** kustomize renames the Secret on
every content change, which is what forces a Helm upgrade. CUE emits a stable
name. The HelmRelease v2 CRD carries `lastAttemptedConfigDigest`, which is
helm-controller digesting the resolved config including `valuesFrom` — so the
upgrade should still happen. Worth confirming empirically once.

All eight `secretGenerator` secrets have since been converted to SOPS
`secret.yaml` manifests, which is what makes this moot: the name is stable by
construction. The conversion was not optional.
CUE has no successor to `secretGenerator`, so a whole-file secret that stays
whole-file is a resource nothing renders. Two fields kustomize used to supply
have to be written by hand — `metadata.namespace` and `type: Opaque` — and both
fail silently if forgotten.

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
  explicit `...`. `#HardenedBase` needed one inside `capabilities` before a
  container could add back `NET_BIND_SERVICE`.
- **An unquoted label shadows a field of the same name.** `chart: spec: {"chart":
chart}` resolves the inner `chart` to the field being declared, not to the
  parameter. Quoting the outer label fixes it, and the error surfaces as a type
  conflict several levels away.
- **A defaulted struct disjunction read from another field drops comprehension
  results.** `values: {...} | *{}` still evaluated correctly as `values`, but
  `out.spec.values` — which reads it — silently lost every field produced by an
  `if` inside it. This is the only trap so far that produced _wrong output_
  rather than an error; the gate caught it. An explicit boolean (`hasValues`)
  replaced the disjunction.
- **Two defaults for one field do not merge.** `string | *""` unified with
  `string | *"4.6.2"` is an unresolved disjunction, so a derived definition
  cannot re-default a field the base already defaulted.
- **A closed definition makes a bad list element type.** `releases: [...#Release]`
  rejected every field `#AppRelease` adds, because the element is re-unified with
  the closed base. The fix is to constrain the list by what the consumer actually
  reads — `[...{out: #HelmRelease, ...}]` — which is also the more honest
  contract.

The mechanics that decide how the tree is _organized_ — package boundaries,
`@tag` propagation, `@embed` path rules — are in
`.okf/architecture/cue-layout.md` rather than repeated here.

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

It recurred a third time in `infrastructure/`. generic-device-plugin hands out
host devices and runs `privileged: true`, and Kubernetes rejects that together
with `allowPrivilegeEscalation: false`, which `#Hardened` pins. So
`#HardenedPrivileged` drops that one field and keeps the rest — the capability
drop and the read-only root still hold, and the exception is one `grep` away.

The same pattern recurred with `#Chain`. qbittorrent's ingress names
`network-internal-whitelist` rather than `chain-network-internal-whitelist`, so
it skips the rate limit, the secure headers and compression that every other
ingress gets. `#Chain` refused it. Rather than widen the type, `bareMiddleware`
names the exception — one `grep` finds it, and whether it was intended is now a
question someone can answer instead of a string nobody reads.

## Not yet evaluated

The delivery mechanism. CUE has to render before Flux sees it; `OCIRepository`
with cosign verification is supported by the running Flux and is the obvious
path, but no pipeline exists here.

<!-- cSpell:ignore chartt -->
