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
	releases: [_nvidia]
}

_nvidia: schema.#Release & {
	name:      "nvidia-device-plugin"
	namespace: bundle.namespace
	chart:     "nvidia-device-plugin"
	// renovate: datasource=helm packageName=nvidia-device-plugin registryUrl=https://nvidia.github.io/k8s-device-plugin
	version:    "0.20.0"
	sourceName: "nvidia-device-plugin"
	interval:   "5m"
	crds:       true

	values: {
		// CDI rather than a containerd runtime handler. k3s registers an `nvidia`
		// handler only when it finds nvidia-container-runtime on its own PATH,
		// which nix-config does not put there; containerd 2.x reads the CDI spec
		// nvidia-container-toolkit writes to /run/cdi instead. A cluster-scoped
		// RuntimeClass named `nvidia` does exist, but k3s owns it as an Addon —
		// this bundle must not create it.
		deviceListStrategy: "cdi-annotations"

		// the plugin and gfd have to see the GPU to enumerate it, and the
		// NVIDIA_VISIBLE_DEVICES the chart sets means nothing without the runtime
		// hook they no longer pass through. This annotation is what injects the
		// driver into their own pods; `all` is a device the spec declares.
		podAnnotations: "cdi.k8s.io/gpu": "nvidia.com/gpu=all"

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
