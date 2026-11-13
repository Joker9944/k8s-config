# OpenCloud recommends the server be off during backup. Both halves — the
# decomposedfs metadata PVC (volsync) and the garage blob bucket (rclone) —
# are captured inside the same scale-down window, so they share a point in
# time. See /platform/backup-and-restore.md in the OKF bundle.

import json
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone

DEPLOY = "deploy/opencloud-opencloud"
SOURCE = "replicationsource/opencloud-source-data"
DST = f"dst:{os.environ['DST_PATH']}"


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def out(*args):
    return run(*args, capture_output=True).stdout


now = datetime.now(timezone.utc)
ts = now.strftime("%Y%m%dT%H%M%S")
cutoff = (now - timedelta(days=28)).strftime("%Y%m%dT%H%M%S")

try:
    run("kubectl", "scale", DEPLOY, "--replicas=0")

    # .status.replicas is omitted once every pod is fully gone, terminating
    # ones included. kubectl wait cannot express field absence, hence the poll.
    for _ in range(60):
        if not out("kubectl", "get", DEPLOY, "-o", "jsonpath={.status.replicas}"):
            break
        time.sleep(5)
    else:
        sys.exit("deployment did not scale down")

    # A manual trigger takes precedence over the schedule for as long as it is
    # set, and Flux never owned the field, so it survives reconciles.
    patch = json.dumps({"spec": {"trigger": {"manual": ts}}})
    run("kubectl", "patch", SOURCE, "--type", "merge", "-p", patch)

    # Runs while the restic mover uploads; blobs are write-once, so this is
    # incremental. --backup-dir keeps deleted/changed objects in dated dirs.
    run(
        "rclone",
        "sync",
        "src:opencloud",
        f"{DST}/current",
        "--backup-dir",
        f"{DST}/deleted/{ts}",
        timeout=3 * 3600,
    )

    # Prune dated dirs by NAME: server-side copies keep original modtimes, so
    # --min-age would purge an old-but-freshly-deleted blob immediately.
    for line in out("rclone", "lsf", "--dirs-only", f"{DST}/deleted").splitlines():
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
finally:
    # The chart runs one replica; never leave the app down after a failure.
    subprocess.run(["kubectl", "scale", DEPLOY, "--replicas=1"])
