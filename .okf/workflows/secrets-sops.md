---
type: Reference
title: Secrets and SOPS
description: How a file's name decides its encryption rule, how the key reaches the cluster, and what stops an unencrypted Secret from being committed.
tags: [sops, age, secrets, security]
resource: .sops.yaml
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-06T20:10:00Z }
---

# The filename is the rule

One age recipient covers the whole repo. `.sops.yaml` has four creation rules, all keyed on the path:

| `path_regex`                | Encrypts                    |
| --------------------------- | --------------------------- |
| `^.*\.sops\.ya?ml`          | the whole file              |
| `^.*(?:/\|\.)secret\.ya?ml` | `^(data\|stringData)$` only |
| `talenv.yaml`               | the whole file              |
| `talsecret.yaml`            | the whole file              |

The partial rule exists so that `apiVersion`, `kind` and `metadata` stay in plaintext and kustomize can still apply namespace, name-prefix and label transforms to the Secret. Fully-encrypted `*.sops.yaml` files are only ever consumed whole — as the file behind a `secretGenerator`, or by talhelper. The first of those goes away with kustomize: CUE has nothing that renders a `secretGenerator`, so those files convert to the partial rule. See [the CUE layout](/architecture/cue-layout.md).

`stores.yaml.indent: 2` pins sops's YAML emitter to the repo's indentation. Its default is 4, which makes every freshly encrypted file fail the formatter — and, for a file whose payload is itself a YAML document, silently changes those bytes.

Renaming a secret file changes how it is encrypted, and changes whether cspell skips it: the ignore list carries `*.sops.yaml` and `*secret.yaml`.

**A name and its content can disagree, and nothing notices.** Creation rules apply on _encryption_; `sops decrypt` and `sops edit` read the rule out of the file's own metadata instead. So a file named for the whole-file rule while its body carries `encrypted_regex` keeps working indefinitely — until the next `sops updatekeys` or re-encrypt follows the filename and swallows `apiVersion` and `kind` too. Renaming costs nothing, because the MAC does not cover the filename.

# Reaching the cluster

`clusters/nyx/bootstrap.sh` creates the `sops-age` Secret in `flux-system` from the age private key, read from stdin. Every level-3 Flux Kustomization then references it through `decryption.provider: sops` / `secretRef: sops-age`, injected by the [`common-sync-patch` component](/architecture/kustomize-components.md) — which is why only level-3 paths can hold SOPS files (see [Flux topology](/architecture/flux-topology.md)).

Talos secrets take a different route entirely: `talenv.yaml` and `talsecret.sops.yaml` are decrypted **locally** by talhelper at render time and never enter the cluster as SOPS documents. See [the cluster](/platform/talos-nyx.md).

# The guardrail

`pkgs/sops-pre-commit.nix` packages the upstream `sops-pre-commit` (`forbid_secrets`), wired into the hook suite against every `*.yaml`/`*.yml`. It fails the commit when a Kubernetes `Secret` is committed unencrypted — the one check standing between a careless `kubectl get secret -o yaml` and the public repository.
