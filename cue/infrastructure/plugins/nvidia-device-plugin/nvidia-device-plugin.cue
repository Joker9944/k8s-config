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

// k3s's `runtimes` Addon ships a RuntimeClass for the `nvidia` handler but none
// for `nvidia-cdi`. Only the CDI handler works here: the plain one runs
// nvidia-container-runtime in auto mode, which reaches for a legacy
// libnvidia-container driver tree a NixOS host does not have, and fails the
// container with exit status 2.
_runtimeClass: {
	apiVersion: "node.k8s.io/v1"
	kind:       "RuntimeClass"
	metadata: name: "nvidia-cdi"
	handler: "nvidia-cdi"
}

_nvidia: schema.#Release & {
	name:      "nvidia-device-plugin"
	namespace: bundle.namespace
	chart:     "nvidia-device-plugin"
	// renovate: datasource=helm packageName=nvidia-device-plugin registryUrl=https://nvidia.github.io/k8s-device-plugin
	version:    "0.20.0"
	sourceName: "nvidia-device-plugin"
	interval:   "5m"

	values: {
		// the plugin needs NVML to enumerate the GPU, which arrives with the driver
		// the handler injects. The chart puts this on the device-plugin and the
		// mps-control DaemonSet.
		runtimeClassName: "nvidia-cdi"

		// the default envvar strategy hands the allocated device to the runtime as
		// NVIDIA_VISIBLE_DEVICES, which CDI mode resolves against /run/cdi. That
		// spec names its devices `0` and `all`, so the id has to be the index —
		// the chart's `uuid` default would ask for a device it does not declare.
		deviceIDStrategy: "index"

		// Both subcharts only label nodes, and nothing in this repo reads a
		// `feature.node.kubernetes.io/*` or `nvidia.com/*` label. The chart's default
		// affinity elects the GPU node from three of them: two are NFD's, and the
		// third, `nvidia.com/gpu.present`, is the chart's own documented override.
		// mother carries that one from nix-config, which is what keeps this
		// DaemonSet on the GPU node with feature discovery gone — drop the label and
		// the plugin matches no node, so `nvidia.com/gpu` leaves mother's allocatable
		// and jellyfin stops scheduling. The subchart condition is
		// `nfd.enabled,gfd.enabled` and Helm takes the first path that exists, so
		// naming nfd.enabled is what decides it rather than gfd's default.
		nfd: enabled: false
		gfd: enabled: false

		// the device-plugin and mps-control DaemonSets share this list. Helm
		// replaces lists rather than merging them, so the chart's own two entries
		// have to be restated.
		tolerations: [
			{key: "CriticalAddonsOnly", operator: "Exists"},
			{key: "nvidia.com/gpu", operator: "Exists", effect: "NoSchedule"},
			schema.#Reserved.any,
		]
	}
}
