package tier

import (
	"github.com/joker9944/k8s-config/schema"
	"github.com/joker9944/k8s-config/apps/cloud/nextcloud"
	"github.com/joker9944/k8s-config/apps/cloud/opencloud"
)

// The cloud tier. Membership is this list: a workload is deployed here because
// it is named, which is what apps/nyx/cloud/cloud-sync.yaml used to say.
tier: schema.#Tier & {
	tree: "apps"
	name: "cloud"

	bundles: {
		"nextcloud": nextcloud.bundle
		"opencloud": opencloud.bundle
	}
}
