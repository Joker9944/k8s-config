---
type: Decision
title: Upgrades roll back, installs do not
description: Every release retries a failed upgrade three times with Helm's rollback strategy so it ends on the last working revision, while install remediation stays off because there it is an uninstall that would delete Helm-managed Postgres clusters.
tags: [flux, helm, remediation, reliability, decision]
status: stable
generated: { by: claude-code/opus-5, at: 2026-10-25T00:00:00Z }
stale_after: 2027-04-25
---

# Decision

`#Release.upgradeRetries` defaults to **3**, rendering `spec.upgrade.remediation.retries`. `strategy` and `remediateLastFailure` are left unset, taking Helm's defaults of `rollback` and — because the count is non-zero — `true`.

`spec.install.remediation` is **never set**, so install retries stay at Helm's default of 0.

`spec.timeout` is 10m and `spec.install.timeout` 60m. [`longhorn`](/platform/storage.md) overrides both directions: `timeout: "30m"` and `upgradeRetries: 0`.

# Why

**Upgrade.** The old behaviour was worse than it appeared. `retries` defaults to 0 — bail after the first failure — so a chart bump that broke an app left the _broken revision deployed and the app down_, with nothing retrying it until the version or values changed. Three retries with rollback inverts that: the release returns to the previous revision between attempts and, since a non-zero count flips `remediateLastFailure`, once more after the last one. The app keeps serving the old version while its HelmRelease stays NotReady, so the failure still alerts.

**Install.** Remediation there is an uninstall, not a retry, and what survives one depends on `helm.sh/resource-policy: keep` — which the fleet sets unevenly. The app-template `persistence` PVCs carry it and StatefulSet volume templates are not in the Helm manifest at all, but blocky's and gotify's cnpg `Cluster`s are Helm-managed with no policy, and their instance PVCs carry the Cluster's `ownerReference`. Uninstalling either would garbage-collect a database that, per [backup and restore](/platform/backup-and-restore.md), has no off-cluster copy. The upside is nil — an install retry without an uninstall is what `interval` already does — so the trade is all downside.

**Timeouts.** `disableWait` defaults to false, so helm-controller waits for the chart's resources before judging an action; these are ceilings on readiness, not delays, and cost nothing while healthy. 10m rather than Helm's 5m default because rollback makes a too-short timeout actively harmful: it would revert a slow-but-healthy upgrade. 60m for install because a restore bootstrap populates a PVC inside the install, and because `upgradeRetries` does not apply there — an overrun install just sits failed.

**Longhorn.** Upstream does not support downgrading Longhorn, so a rollback would re-apply the previous chart's manifests over a live storage layer. A failed upgrade there has to stay failed for a human. Its 30m timeout exists so a manager DaemonSet and CSI plugins rolling across four nodes is never _mistaken_ for a failure in the first place, and its bundle carries 35m so the Kustomization does not fail while Helm is still working.

# What this replaced

A single `_lifecycle` value welded Helm's CRD policy to a retry count and was applied only `if crds`, so exactly the three charts with a real Helm `crds/` directory — traefik, redis-operator, kube-prometheus-stack — had remediation, by side effect rather than by choice. The other releases had none and could not ask for it. `crds` now means only what its name says.
