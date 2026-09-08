# Platform

The services nyx runs so that everything else can run.

- [The nyx cluster](cluster-nyx.md) - node inventory, the label and taint scheme, and what lives outside this repo.
- [Networking and ingress](networking-and-ingress.md) - MetalLB, Traefik, and the three middleware chains.
- [Certificates and PKI](certificates-and-pki.md) - the public ACME wildcard, the private CA chain, and how both are distributed.
- [Identity — kanidm](identity-kanidm.md) - the OIDC provider, and why client registration is manual.
- [Storage](storage.md) - the three Longhorn classes, NFS media, and Garage object storage.
- [Backup and restore](backup-and-restore.md) - volsync/restic for PVCs, CNPG/barman-cloud for Postgres.
- [Observability](observability.md) - Prometheus, Loki, Alloy, and the Gotify alerting path.
