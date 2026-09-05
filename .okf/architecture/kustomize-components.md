---
type: Architecture
title: Kustomize components and the PLACEHOLDER conventions
description: The shared components/ tree, what each component injects, and the two distinct mechanisms that both spell their unresolved value PLACEHOLDER.
tags: [kustomize, dry, components]
resource: components
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-05T19:20:00Z }
---

# Components

Every directory under `components/` is a `kustomize.config.k8s.io/v1alpha1` `Component`, pulled in through a `components:` list with a relative path.

| Component                 | Users | Effect                                                                                                                                                                                                                                          |
| ------------------------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `common-kustomizeconfig`  | 34    | `configurations:` teaching kustomize two HelmRelease field paths — `spec/valuesFrom/name` is a Secret/ConfigMap name reference (so generator hash suffixes propagate), and `spec/chart/spec/sourceRef/namespace` takes the namespace transform. |
| `common-middlewares`      | 15    | Installs the Traefik `Middleware` set into the namespace. See [ingress](/platform/networking-and-ingress.md).                                                                                                                                   |
| `bjw-s-helm-repository`   | 13    | The `bjw-s` `HelmRepository`.                                                                                                                                                                                                                   |
| `common-sync-patch`       | 8     | Patches every `Kustomization` in an overlay directory with interval/timeout/prune, `sourceRef` → `flux-system`, and SOPS decryption via the `sops-age` Secret. See [Flux topology](/architecture/flux-topology.md).                             |
| `ot-helm-helm-repository` | 3     | The `ot-helm` `HelmRepository` (Redis operator charts).                                                                                                                                                                                         |
| `namespace-cert-kanidm`   | 1     | A wildcard `*.<ns>.svc.cluster.local` Certificate issued by `nyx-intermediate-ca`.                                                                                                                                                              |
| `namespace-cert`          | 0     | The same component without the hardcoded namespace. Currently unused.                                                                                                                                                                           |

`Middleware` and `HelmRepository` are namespaced, which is why those components are pulled in once per namespace rather than installed cluster-wide.

# PLACEHOLDER

Two unrelated mechanisms both use the literal `PLACEHOLDER` for a value kustomize fills in.

**Namespace transformer.** `manifests/namespace.yaml` is written as `metadata.name: PLACEHOLDER`. Kustomize's namespace transformer rewrites `metadata.name` on `Namespace` resources, so the real name comes from `namespace:` in the app's `kustomization.yaml`. The literal is never meant to survive the build.

**`replacements`.** A namespace embedded _inside_ a longer string is out of the transformer's reach, so it is written as a `PLACEHOLDER` segment and rewritten by a `replacements` rule sourced from the resource's own `metadata.namespace`, splitting on a delimiter and overwriting one index:

```yaml
replacements:
  - source: { kind: HelmRelease, name: garage, fieldPath: metadata.namespace }
    targets:
      - select: { kind: HelmRelease, name: garage }
        fieldPaths:
          - spec.values.ingress.s3.api.annotations.[traefik.ingress.kubernetes.io/router.middlewares]
        options: { delimiter: "-", index: 0 }
```

# Traps

- **The `replacements` convention is not universal.** Only `infrastructure/base/{garage,kanidm,kube-prometheus-stack,longhorn}` declare it. Every `apps/base/*` ingress instead **hardcodes** its namespace in the middleware annotation (`jellyfin-chain-country-whitelist@kubernetescrd`) under a `TODO`. Copying an app manifest into a differently-named namespace silently points at a middleware that does not exist there.
- **`namespace-cert-kanidm` duplicates `namespace-cert`.** It is the same component plus a hardcoded `namespace: kanidm`, working around [kustomize#5953](https://github.com/kubernetes-sigs/kustomize/issues/5953). Editing one without the other diverges them, and the unused original is the one that looks canonical.
- **Per-app `configurations:` escape hatches.** `apps/base/{blocky,komga}/kustomize/kustomization-hack.yaml` add `nameReference` entries for `spec/values/persistence/*/name`, because those chart values reference a generated ConfigMap that `common-kustomizeconfig` does not cover. Both are marked `TODO find a way to replace this ugly hack`; the shared component carries the matching `TODO This is dumb, find a way to DRY this.`
