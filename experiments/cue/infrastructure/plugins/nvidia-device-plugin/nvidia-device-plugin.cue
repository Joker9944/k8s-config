package nvidiadeviceplugin

// cSpell:ignore gpus nvidiadeviceplugin

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace:   "nvidia-device-plugin"
	source:      "infrastructure/base/nvidia-device-plugin"
	middlewares: false
	repositories: [
		schema.#HelmRepo & {name: "nvidia-device-plugin", url: "https://nvidia.github.io/k8s-device-plugin"},
	]
	namespaceLabels: {
		"pod-security.kubernetes.io/enforce": "privileged"
		"pod-security.kubernetes.io/warn":    "privileged"
		"pod-security.kubernetes.io/audit":   "privileged"
	}
	before: [_runtimeClass]
	releases: [_nvidia]
}

// Talos registers the nvidia container runtime under this handler; the chart
// only references the class, it does not create it.
_runtimeClass: {
	apiVersion: "node.k8s.io/v1"
	kind:       "RuntimeClass"
	metadata: name: "nvidia"
	handler: "nvidia"
}

_nvidia: schema.#Release & {
	name:       "nvidia-device-plugin"
	namespace:  bundle.namespace
	chart:      "nvidia-device-plugin"
	version:    "0.19.3"
	sourceName: "nvidia-device-plugin"
	interval:   "5m"
	crds:       true

	values: {
		runtimeClassName: _runtimeClass.metadata.name
		gfd: enabled:              true
		nfd: enableNodeFeatureApi: true
	}
}
