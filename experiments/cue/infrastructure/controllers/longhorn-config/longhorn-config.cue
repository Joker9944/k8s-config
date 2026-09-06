package longhornconfig

// cSpell:ignore longhornconfig

import (
	"list"
	"github.com/joker9944/k8s-config/schema"
)

bundle: schema.#ConfigBundle & {
	source: "infrastructure/nyx/config/longhorn"
	resources: list.Concat([_storageClasses, [_snapshotClass]])
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
