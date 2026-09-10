@extern(embed)

package alloy

import (
	"strings"

	"github.com/joker9944/k8s-config/schema"
)

bundle: schema.#Bundle & {
	namespace: "alloy"
	dependsOn: ["loki"]
	middlewares: false
	repositories: [_grafana]
	before: [_config.out]
	releases: [_alloy]
}

_grafana: schema.#HelmRepo & {name: "grafana", url: "https://grafana.github.io/helm-charts"}

// Plaintext config, read from disk at evaluation time. @embed cannot escape the
// package directory, which is why this file lives here.
_configAlloy: _ @embed(file="files/config.alloy", type=text)
_klogAlloy:   _ @embed(file="files/klog.alloy", type=text)

// Delivered into /etc/alloy.d by the same sidecar that carries the workload
// files, so the base and the pipelines that reference it arrive together. Both
// keys ride the one ConfigMap, which is what stops config.alloy's reference into
// klog.alloy from ever resolving against a directory that lacks it.
_config: schema.#ConfigMapFiles & {
	name: "alloy-config"
	ns:   bundle.namespace
	labels: alloy_config: "1"
	files: {
		"config.alloy": _configAlloy
		"klog.alloy":   _klogAlloy
	}
}

// Watches every namespace for ConfigMaps carrying alloy_config and writes each
// key into the shared directory. The LIST pass is an init container so the base
// is on disk before alloy starts; the WATCH pass keeps it current and reloads.
// Alloy's own ClusterRole already grants cluster-wide configmap get/list/watch
// and a sidecar shares the pod's ServiceAccount, so this needs no extra RBAC.
_sidecar: {
	_method: string

	name:  "config-sidecar-\(strings.ToLower(_method))"
	image: "quay.io/kiwigrid/k8s-sidecar:2.5.0"
	env: [
		{name: "METHOD", value: _method},
		{name: "LABEL", value: "alloy_config"},
		{name: "LABEL_VALUE", value: "1"},
		{name: "RESOURCE", value: "configmap"},
		{name: "NAMESPACE", value: "ALL"},
		{name: "FOLDER", value: _configDir},
		if _method == "WATCH" {{name: "REQ_URL", value: "http://localhost:12345/-/reload"}},
		if _method == "WATCH" {{name: "REQ_METHOD", value: "POST"}},
	]
	volumeMounts: [{name: "alloy-d", mountPath: _configDir}]
}

_configDir: "/etc/alloy.d"

_alloy: schema.#Release & {
	name:      "alloy"
	namespace: bundle.namespace
	chart:     "alloy"
	// renovate: datasource=helm packageName=alloy registryUrl=https://grafana.github.io/helm-charts
	version:    "1.12.1"
	sourceName: _grafana.name

	// The CRDs come with the loki release, which is why this one installs none.
	// The chart is pointed at the ConfigMap above rather than templating its own;
	// upstream asks for exactly this when the config is managed outside the chart.
	values: {
		alloy: {
			configMap: {
				create: false
				name:   _config.name

				// HACK `key` is interpolated straight into the args as
				// `run /etc/alloy/<key>`, so escaping the directory is what points
				// `run` at a path the sidecar can write — and a directory rather
				// than a file is what makes alloy load every *.alloy in it as one
				// graph. The chart hardcodes the config volume as a ConfigMap, so
				// it cannot be swapped for the emptyDir instead; `name` above still
				// mounts that ConfigMap at /etc/alloy, where nothing reads it.
				// Retire this when the chart can be pointed at a config directory
				// (https://github.com/grafana/alloy/issues/1176, PR #1016 open
				// since 2024).
				key: "../alloy.d"
			}

			// Builds the alloy-cluster headless Service and passes
			// --cluster.enabled. The config's clustering blocks are inert without
			// it, which is what let four replicas ship the same lines.
			clustering: enabled: true

			mounts: extra: [{name: "alloy-d", mountPath: _configDir}]
		}

		// The chart's own reloader watches /etc/alloy, which is no longer the
		// path alloy reads. The WATCH sidecar owns reloads instead.
		configReloader: enabled: false

		controller: {
			tolerations: [schema.#Reserved.any]
			volumes: extra: [{name: "alloy-d", emptyDir: {}}]
			initContainers: [_sidecar & {_method: "LIST"}]
			extraContainers: [_sidecar & {_method: "WATCH"}]
		}
	}
}
