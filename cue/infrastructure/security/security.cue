package tier

import (
	"github.com/joker9944/k8s-config/schema"
	"github.com/joker9944/k8s-config/infrastructure/security/kanidm"
	kanidmcluster "github.com/joker9944/k8s-config/infrastructure/security/kanidm-cluster:kanidmcluster"
	kanidmoperator "github.com/joker9944/k8s-config/infrastructure/security/kanidm-operator:kanidmoperator"
)

// The security tier. Membership is this list: a workload is deployed here
// because it is named here, and nowhere else.
tier: schema.#Tier & {
	tree: "infrastructure"
	name: "security"

	bundles: {
		"kanidm":          kanidm.bundle
		"kanidm-operator": kanidmoperator.bundle
		"kanidm-cluster":  kanidmcluster.bundle
	}
}
