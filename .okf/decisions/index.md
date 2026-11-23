# Decisions

Choices with rationale, tied to the state they produced.

- [Replace kustomize with CUE](replace-kustomize-with-cue.md) - CUE composes, Flux and app-template stay, manifests ship as a signed OCI artifact.
- [One manifests artifact](single-manifests-artifact.md) - every bundle ships in `nyx-manifests`; tiers are gone and rendering stays in CI.
- [Jellyfin's config is not declared](jellyfin-config-not-declared.md) - the settings stay in the volume; the repo declares the deployment.
- [Jellyfin's SSO plugin is the maintained fork](jellyfin-sso-plugin.md) - the fork shares 9p4's plugin GUID, so adopting it is an upgrade rather than a migration.
- [Upgrades roll back, installs do not](helm-remediation-policy.md) - rollback-and-retry on upgrade; install remediation is an uninstall that would delete Postgres.
