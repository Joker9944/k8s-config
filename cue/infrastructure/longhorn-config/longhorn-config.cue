package longhornconfig

// cSpell:ignore longhornconfig

import (
	"list"
	"github.com/joker9944/k8s-config/schema"
)

bundle: schema.#ConfigBundle & {
	needs: ["block-storage"]
	resources: list.Concat([_storageClasses, [_snapshotClass], _reclaimJobs])
}

// Both classes keep one replica and expand on demand; they differ only in how
// strictly a volume is pinned to the node writing it. /platform/storage.md says
// which workload wants which.
_storageClasses: [for name, locality in {
	"longhorn-local-strict": "strict-local"
	"longhorn-local-lax":    "best-effort"
} {
	apiVersion: "storage.k8s.io/v1"
	kind:       "StorageClass"
	metadata: "name": name
	provisioner:          "driver.longhorn.io"
	allowVolumeExpansion: true
	parameters: {
		dataLocality:     locality
		numberOfReplicas: "1"
	}
}]

_snapshotClass: {
	apiVersion: "snapshot.storage.k8s.io/v1"
	kind:       "VolumeSnapshotClass"
	metadata: name: "longhorn"
	driver:         "driver.longhorn.io"
	deletionPolicy: "Delete"
	parameters: type: "snap"
}

// Three different mechanisms leave bytes behind on a Longhorn disk and no one
// task addresses more than one, so all three run — staggered, so each sees the
// previous stage's result, and clear of the midnight volsync window. They run
// in the `default` group, which Longhorn applies to every volume that names no
// job of its own, so nothing is labelled per volume; giving one volume an
// explicit job silently drops it out of the group.
//
//   snapshot-delete  — Longhorn keeps the snapshot a CSI clone is taken from
//     and never reaps it, so every volsync `Clone` source gains one per daily
//     run, forever. This is the only task that considers every snapshot on the
//     volume rather than just the ones its own job created, which is what
//     reaches a clone's. It need not purge: deleting the CR is enough, because
//     the snapshot controller purges on MarkRemoved and attaches a detached
//     volume to do it. The corollary is that it overrules any other job's
//     retention on the same volume.
//   snapshot-cleanup — deletes nothing; it is only a volume-wide purge. That is
//     for the snapshot a replica rebuild leaves marked removed but pinning its
//     whole size, which the controller skips for as long as it is the parent of
//     volume-head rather than hold the volume attached.
//   filesystem-trim  — neither of the above discards blocks the guest
//     filesystem freed, which is the larger waste: a volume reads as full at
//     its reserved size while holding a fraction of that. Last in the sequence
//     because `remove-snapshots-during-filesystem-trim` is false, so trim
//     reaches only what the two purges above have already collapsed into
//     volume-head.
_reclaimJobs: [for name, job in {
	"snapshot-prune": {task: "snapshot-delete", cron: "0 4 * * *", retain: 2}
	"snapshot-purge": {task: "snapshot-cleanup", cron: "30 4 * * *"}
	"filesystem-trim": {task: "filesystem-trim", cron: "0 5 * * *"}
} {
	apiVersion: "longhorn.io/v1beta2"
	kind:       "RecurringJob"
	metadata: {
		"name":    name
		namespace: "longhorn-system"
	}
	spec: job & {
		// A purge rewrites the snapshot chain on disk and a trim discards across
		// the whole volume; the global snapshot-heavy-task-concurrent-limit of 5
		// would put 58 volumes against the NVMe the workloads are also on.
		concurrency: 2
		groups: ["default"]
	}
}]
