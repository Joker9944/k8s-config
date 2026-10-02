---
type: Reference
title: Jellyfin's config
description: Where Jellyfin keeps its settings inside the config volume, how to read them, and what to watch for when changing a file directly.
tags: [jellyfin, config, kubectl]
status: stable
generated: { by: claude-code/opus-5, at: 2026-10-02T10:20:08Z }
---

# Where it lives

All of it is in the `config` volume, mounted at `/config`.

| Path                                 | Holds                                                         |
| ------------------------------------ | ------------------------------------------------------------- |
| `/config/config/`                    | server settings, mostly XML — encoding, network, branding     |
| `/config/plugins/`                   | installed plugins, and their settings under `configurations/` |
| `/config/data/`                      | `jellyfin.db` — library, users, watch state                   |
| `/config/metadata/`, `/config/root/` | fetched artwork, library roots                                |
| `/config/log/`                       | Jellyfin's own rolling log files                              |

The log directory is Serilog's file sink. What reaches Loki is the console sink
off container stdout, by way of `files/jellyfin.alloy` — not these files.

# Reading it

The dashboard at `jellyfin.vonarx.online` is the interface. The volume is for
inspection:

```sh
kubectl -n jellyfin exec jellyfin-0 -- ls /config/config
kubectl -n jellyfin exec jellyfin-0 -- cat /config/config/system.xml
```

# What to expect

Some configs under `/config/plugins/configurations/` carry credentials in
plaintext — the [kanidm](/platform/identity-kanidm.md) client secret among them —
so they are not safe to paste into an issue or a chat.

Editing a file directly works, and is sometimes the only way to set something the
dashboard will not expose. It bypasses the dashboard's validation, so a malformed
or out-of-range value lands unchecked: restart the workload to pick the change up,
then confirm it took.

The volume itself is described in [storage](/platform/storage.md). Why none of
this is declared in the repo is
[its own decision](/decisions/jellyfin-config-not-declared.md).
