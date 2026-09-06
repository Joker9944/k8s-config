package security

import (
	"github.com/joker9944/k8s-config/schema"
	"github.com/joker9944/k8s-config/infrastructure/security/kanidm"
)

// The security tier. Membership is this list: a workload is deployed here
// because it is named, which is what
// infrastructure/nyx/security/security-sync.yaml used to say.
tier: schema.#Tier & {
	bundles: {
		"kanidm": kanidm.bundle
	}
}
