package utility

import (
	"github.com/joker9944/k8s-config/schema"
	"github.com/joker9944/k8s-config/apps/utility/blocky"
	"github.com/joker9944/k8s-config/apps/utility/pgadmin"
)

// The utility tier. Membership is this list: a workload is deployed here because
// it is named, which is what apps/nyx/utility/utility-sync.yaml used to say.
tier: schema.#Tier & {
	bundles: {
		"blocky":  blocky.bundle
		"pgadmin": pgadmin.bundle
	}
}
