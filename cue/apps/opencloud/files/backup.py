# OpenCloud recommends the server be off during backup. Both halves — the
# decomposedfs metadata PVC (volsync) and the garage blob bucket (rclone) —
# are captured inside the same scale-down window, so they share a point in
# time. See /platform/backup-and-restore.md in the OKF bundle.

import json
import os
import signal
import subprocess
import sys
import time
from datetime import UTC, datetime, timedelta

# Python dies on SIGTERM without unwinding; route it through `finally` so a
# drained, evicted or deleted pod still scales the app back up.
signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))

DEPLOY = "deploy/opencloud-opencloud"
HELMRELEASE = "helmreleases.helm.toolkit.fluxcd.io/opencloud"
SOURCE = "replicationsource/opencloud-source-data"
PVC = "pvc/opencloud-opencloud-data"
DST = f"dst:{os.environ['DST_PATH']}"
SOURCE_MANIFEST = json.loads(os.environ["SOURCE_MANIFEST"])
RCLONE_DIR_NOT_FOUND = 3


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def out(*args):
    return run(*args, capture_output=True).stdout


def suspend(value):
    patch = json.dumps({"spec": {"suspend": value}})
    run("kubectl", "patch", HELMRELEASE, "--type", "merge", "-p", patch)


now = datetime.now(UTC)
ts = now.strftime("%Y%m%dT%H%M%S")
cutoff = (now - timedelta(days=28)).strftime("%Y%m%dT%H%M%S")

labels = json.loads(out("kubectl", "get", DEPLOY, "-o", "jsonpath={.spec.selector.matchLabels}"))
selector = ",".join(f"{k}={v}" for k, v in labels.items())

# A new manual trigger does not interrupt a running sync; it would be credited
# to that sync instead. Bail out before taking the app down.
current = out("kubectl", "get", SOURCE, "--ignore-not-found", "-o", "json")
if current:
    current = json.loads(current)
    manual = current["spec"].get("trigger", {}).get("manual")
    if manual != current.get("status", {}).get("lastManualSync"):
        sys.exit(f"previous sync {manual} has not finished")

try:
    # Any Helm upgrade resets replicas; Flux never owned spec.suspend, so a
    # reconcile does not undo this.
    suspend(True)
    run("kubectl", "scale", DEPLOY, "--replicas=0")

    # The Deployment stops counting a pod once it is marked for deletion, so
    # only the pods themselves show when storage-users has finished flushing.
    for _ in range(60):
        if not out("kubectl", "get", "pods", "-l", selector, "-o", "name"):
            break
        time.sleep(5)
    else:
        sys.exit("opencloud pods did not terminate")

    # The script owns the ReplicationSource; a new manual value starts one sync.
    # Created here on the first run, so its initial sync is quiesced too.
    SOURCE_MANIFEST["spec"]["trigger"] = {"manual": ts}
    run(
        "kubectl",
        "apply",
        "--server-side",
        "--field-manager=opencloud-backup",
        "-f",
        "-",
        input=json.dumps(SOURCE_MANIFEST),
    )

    # The PVC carries use-copy-trigger: volsync clones it only once copy-trigger
    # changes, and echoes the value into latest-copy-trigger when the clone is
    # bound. From then on the volume half is fixed and a failure is safe.
    run("kubectl", "annotate", "--overwrite", PVC, f"volsync.backube/copy-trigger={ts}")
    run(
        "kubectl",
        "wait",
        PVC,
        f"--for=jsonpath={{.metadata.annotations.volsync\\.backube/latest-copy-trigger}}={ts}",
        "--timeout",
        "30m",
    )

    # Blobs are write-once, so this is incremental. --backup-dir keeps
    # deleted/changed objects in dated dirs.
    run(
        "rclone",
        "sync",
        "src:opencloud",
        f"{DST}/current",
        "--backup-dir",
        f"{DST}/deleted/{ts}",
        timeout=3 * 3600,
    )
finally:
    # A second SIGTERM must not abort the scale-up. A failed scale-up raises,
    # failing the Job even when the backup succeeded.
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    try:
        run("kubectl", "scale", DEPLOY, "--replicas=1")
    finally:
        suspend(False)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)

# Nothing below needs the app down.

# Prune dated dirs by NAME: server-side copies keep original modtimes, so
# --min-age would purge an old-but-freshly-deleted blob immediately.
# deleted/ does not exist until the first sync moves something into it.
listing = subprocess.run(
    ["rclone", "lsf", "--dirs-only", f"{DST}/deleted"], capture_output=True, text=True
)
if listing.returncode not in (0, RCLONE_DIR_NOT_FOUND):
    sys.exit(listing.stderr)
for line in listing.stdout.splitlines():
    name = line.rstrip("/")
    if name < cutoff:
        run("rclone", "purge", f"{DST}/deleted/{name}")

run(
    "kubectl",
    "wait",
    SOURCE,
    f"--for=jsonpath={{.status.lastManualSync}}={ts}",
    "--timeout",
    "2h",
)
