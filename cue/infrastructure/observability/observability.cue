package tier

// cSpell:ignore kubeprometheusstack traefikobservabilityconfig

import (
	"github.com/joker9944/k8s-config/schema"
	"github.com/joker9944/k8s-config/infrastructure/observability/alloy"
	"github.com/joker9944/k8s-config/infrastructure/observability/gotify"
	kubeprometheusstack "github.com/joker9944/k8s-config/infrastructure/observability/kube-prometheus-stack:kubeprometheusstack"
	"github.com/joker9944/k8s-config/infrastructure/observability/loki"
	traefikobservabilityconfig "github.com/joker9944/k8s-config/infrastructure/observability/traefik-observability-config:traefikobservabilityconfig"
)

// The observability tier. Membership is this list: a workload is deployed here
// because it is named here, and nowhere else.
tier: schema.#Tier & {
	tree: "infrastructure"
	name: "observability"

	bundles: {
		"alloy":                        alloy.bundle
		"gotify":                       gotify.bundle
		"kube-prometheus-stack":        kubeprometheusstack.bundle
		"loki":                         loki.bundle
		"traefik-observability-config": traefikobservabilityconfig.bundle
	}
}
