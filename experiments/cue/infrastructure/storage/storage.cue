package tier

import (
	"github.com/joker9944/k8s-config/schema"
	"github.com/joker9944/k8s-config/infrastructure/storage/garage"
)

// The storage tier. Membership is this list: a workload is deployed here because
// it is named, which is what infrastructure/nyx/storage/storage-sync.yaml used
// to say.
tier: schema.#Tier & {
	tree: "infrastructure"
	name: "storage"

	bundles: {
		"garage": garage.bundle
	}
}
