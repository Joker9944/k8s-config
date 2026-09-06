package tier

// cSpell:ignore kubeprometheusstack

import (
	"github.com/joker9944/k8s-config/schema"
	"github.com/joker9944/k8s-config/infrastructure/observability/alloy"
	"github.com/joker9944/k8s-config/infrastructure/observability/gotify"
	kubeprometheusstack "github.com/joker9944/k8s-config/infrastructure/observability/kube-prometheus-stack:kubeprometheusstack"
	"github.com/joker9944/k8s-config/infrastructure/observability/loki"
)

// The observability tier. Membership is this list: a workload is deployed here
// because it is named, which is what
// infrastructure/nyx/observability/observability-sync.yaml used to say.
tier: schema.#Tier & {
	tree: "infrastructure"
	name: "observability"

	bundles: {
		"alloy":                 alloy.bundle
		"gotify":                gotify.bundle
		"kube-prometheus-stack": kubeprometheusstack.bundle
		"loki":                  loki.bundle
	}
}
