package nvidiadeviceplugin

// cSpell:ignore gpus nvidiadeviceplugin

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace:   "nvidia-device-plugin"
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

// The node's container runtime registers the nvidia handler; the chart only
// references the class, it does not create it.
_runtimeClass: {
	apiVersion: "node.k8s.io/v1"
	kind:       "RuntimeClass"
	metadata: name: "nvidia"
	handler: "nvidia"
}

_nvidia: schema.#Release & {
	name:      "nvidia-device-plugin"
	namespace: bundle.namespace
	chart:     "nvidia-device-plugin"
	// renovate: datasource=helm packageName=nvidia-device-plugin registryUrl=https://nvidia.github.io/k8s-device-plugin
	version:    "0.19.3"
	sourceName: "nvidia-device-plugin"
	interval:   "5m"
	crds:       true

	values: {
		runtimeClassName: _runtimeClass.metadata.name
		gfd: enabled: true
		nfd: {
			enableNodeFeatureApi: true
			// the feature-discovery worker labels the node, so it has to reach the
			// reserved one too
			worker: tolerations: [
				{key: "node-role.kubernetes.io/master", operator: "Equal", value: "", effect: "NoSchedule"},
				{key: "nvidia.com/gpu", operator: "Equal", value: "present", effect: "NoSchedule"},
				schema.#Reserved.any,
			]
		}

		// the device-plugin, gfd and mps-control DaemonSets share this list. Helm
		// replaces lists rather than merging them, so the chart's own two entries
		// have to be restated.
		tolerations: [
			{key: "CriticalAddonsOnly", operator: "Exists"},
			{key: "nvidia.com/gpu", operator: "Exists", effect: "NoSchedule"},
			schema.#Reserved.any,
		]
	}
}
