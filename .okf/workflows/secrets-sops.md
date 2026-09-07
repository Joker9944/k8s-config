---
type: Reference
title: Secrets and SOPS
description: How a file's name decides its encryption rule, how the key reaches the cluster, and what stops an unencrypted Secret from being committed.
tags: [sops, age, secrets, security]
resource: .sops.yaml
status: stable
generated: { by: claude-code/opus-5, at: 2026-09-07T22:00:00Z }
---

# The filename is the rule

One age recipient covers the whole repo. `.sops.yaml` has four creation rules, all keyed on the path:

| `path_regex`                | Encrypts                    |
| --------------------------- | --------------------------- |
| `^.*\.sops\.ya?ml`          | the whole file              |
| `^.*(?:/\|\.)secret\.ya?ml` | `^(data\|stringData)$` only |
| `talenv.yaml`               | the whole file              |
| `talsecret.yaml`            | the whole file              |

The partial rule leaves `apiVersion`, `kind` and `metadata` readable, which is why a file can be identified without the key. Every Kubernetes secret in the repo uses it. The whole-file rule now has exactly one user left — `clusters/nyx/talos/talsecret.sops.yaml`, which talhelper consumes whole and which never enters the cluster as a SOPS document.

`stores.yaml.indent: 2` pins sops's YAML emitter to the repo's indentation. Its default is 4, which makes every freshly encrypted file fail the formatter — and, for a file whose payload is itself a YAML document, silently changes those bytes.

Renaming a secret file changes how it is encrypted, and changes whether cspell skips it: the ignore list carries `*.sops.yaml` and `*secret.yaml`. Names are load-bearing beyond that — `cue/<workload>/secrets/restic.secret.yaml` holds volsync credentials and nothing else, because [`#VolsyncRestic`](/architecture/cue-layout.md) takes that path as an input.

**The MAC covers the whole file, not each document.** Every document in a multi-document file carries its own `sops:` block, which makes deleting one look like a text edit. It is not: the MAC in the surviving block was computed over all of them, and the file stops decrypting. Removing a Secret from such a file means decrypt, drop the document, re-encrypt — and the re-encrypt has to happen at a path matching a creation rule, or sops exits with `no matching creation rules found` and whatever plaintext is in flight stays plaintext.

**A name and its content can disagree, and nothing notices.** Creation rules apply on _encryption_; `sops decrypt` and `sops edit` read the rule out of the file's own metadata instead. So a file named for the whole-file rule while its body carries `encrypted_regex` keeps working indefinitely — until the next `sops updatekeys` or re-encrypt follows the filename and swallows `apiVersion` and `kind` too. Renaming costs nothing, because the MAC does not cover the filename.

# Reaching the cluster

`clusters/nyx/bootstrap.sh` creates the `sops-age` Secret in `flux-system` from the age private key, read from stdin. Every level-3 Flux Kustomization then references it through `decryption.provider: sops` / `secretRef: sops-age`, set by `#Tier.sync` — which is why a SOPS file has to sit in a bundle directory inside the artifact rather than at its root (see [Flux topology](/architecture/flux-topology.md)).

Talos secrets take a different route entirely: `talenv.yaml` and `talsecret.sops.yaml` are decrypted **locally** by talhelper at render time and never enter the cluster as SOPS documents. See [the cluster](/platform/talos-nyx.md).

# The guardrail

`pkgs/sops-pre-commit.nix` packages the upstream `sops-pre-commit` (`forbid_secrets`), wired into the hook suite against every `*.yaml`/`*.yml`. It fails the commit when a Kubernetes `Secret` is committed unencrypted — the one check standing between a careless `kubectl get secret -o yaml` and the public repository.
