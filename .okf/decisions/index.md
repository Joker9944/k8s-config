# Decisions

Choices with rationale, tied to the state they produced.

- [Replace kustomize with CUE](replace-kustomize-with-cue.md) - CUE composes, Flux and app-template stay, manifests ship as per-tier OCI artifacts.
- [Jellyfin's config is not declared](jellyfin-config-not-declared.md) - the settings stay in the volume; the repo declares the deployment.
- [Upgrades roll back, installs do not](helm-remediation-policy.md) - rollback-and-retry on upgrade; install remediation is an uninstall that would delete Postgres.
