package longhorn

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "longhorn-system"

	// Waiting here also gates the two snapshot Kustomizations in `after`, which
	// is where the VolumeSnapshotClass CRD longhorn-config needs comes from —
	// the one thing a plain edge to longhorn never covered. The timeout exceeds
	// the release's own, so the Kustomization never fails while Helm is still
	// rolling out.
	wait:    true
	timeout: "35m"
	repositories: [
		schema.#HelmRepo & {name: "longhorn", url: "https://charts.longhorn.io"},
		_snapshotter,
	]
	namespaceLabels: {
		"pod-security.kubernetes.io/enforce": "privileged"
		"pod-security.kubernetes.io/warn":    "privileged"
		"pod-security.kubernetes.io/audit":   "privileged"
	}
	after: _snapshotSync
	releases: [_longhorn]
}

// The volume-snapshot CRDs and their controller are not part of the longhorn
// chart; they come straight out of the upstream repository, reconciled by two
// Kustomizations of their own.
_snapshotter: schema.#GitRepo & {
	name: "external-snapshotter"
	url:  "https://github.com/kubernetes-csi/external-snapshotter"
	// renovate: datasource=git-tags packageName=https://github.com/kubernetes-csi/external-snapshotter
	tag: "v8.7.0"
}

_snapshotSync: [for k, path in {
	"snapshot-crds":       "./client/config/crd"
	"snapshot-controller": "./deploy/kubernetes/snapshot-controller"
} {
	apiVersion: "kustomize.toolkit.fluxcd.io/v1"
	kind:       "Kustomization"
	metadata: {name: k, namespace: bundle.namespace}
	spec: {
		interval: "10m"
		timeout:  "1m"
		sourceRef: {kind: "GitRepository", name: _snapshotter.name}
		"path": path
		prune:  true
	}
}]

_longhorn: schema.#Release & {
	name:      "longhorn"
	namespace: bundle.namespace
	chart:     "longhorn"
	// renovate: datasource=helm packageName=longhorn registryUrl=https://charts.longhorn.io
	version:    "1.13.0"
	sourceName: "longhorn"

	// A manager DaemonSet plus CSI plugins roll across all four nodes, so the
	// fleet default is far too tight. And no rollback: upstream does not support
	// downgrading Longhorn, so a failed upgrade must stay failed for a human
	// rather than re-applying the previous chart over a live storage layer.
	timeout:        "30m"
	upgradeRetries: 0

	host:  "longhorn.vonarx.online"
	chain: "chain-network-internal-whitelist"

	values: {
		// longhorn has to run on the reserved node — that is where the storage is.
		// defaultSettings covers the system-managed components (instance-manager,
		// engine-image, CSI plugins), which take a taint string rather than a
		// pod-spec toleration.
		defaultSettings: taintToleration: schema.#Reserved.taint
		longhornManager: tolerations: [schema.#Reserved.any]

		persistence: defaultDataLocality: "best-effort"

		// the longhorn chart takes one ingress, not a keyed set
		ingress: {
			enabled:     true
			annotations: _longhorn.ingressAnnotations
			"host":      host
			tls:         true
			tlsSecret:   "wildcard-vonarx-online-cert"
		}
	}
}
