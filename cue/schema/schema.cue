package schema

import "list"

// ---------------------------------------------------------------- constraints
// House style, enforced by the type checker rather than by review.

// Images must be pinned by tag AND digest.
#Digest: =~"^[^@]+@sha256:[0-9a-f]{64}$"

// Every container in the fleet is hardened. Not overridable per-app: an
// exception has to be spelled with a different definition, so `grep` finds it.
#Hardened: #HardenedBase & {
	securityContext: readOnlyRootFilesystem: true
}

// The sanctioned exception, for images that will not run on a read-only root.
// Using this is a policy decision and should stay rare.
#HardenedWritableRoot: #HardenedBase & {
	securityContext: readOnlyRootFilesystem: false
}

// The sanctioned exception for a container that has to run privileged.
// Kubernetes rejects `privileged: true` together with
// `allowPrivilegeEscalation: false`, so this one drops the field rather than the
// constraint; the capability drop and the read-only root still hold.
// generic-device-plugin is the only user, and it is privileged because it hands
// out host devices.
#HardenedPrivileged: #PinnedImage & {
	securityContext: {
		privileged:             true
		readOnlyRootFilesystem: true
		capabilities: {drop: ["ALL"], ...}
		...
	}
}

#HardenedBase: #PinnedImage & {
	securityContext: {
		allowPrivilegeEscalation: false
		// open: a container may add back a capability it genuinely needs
		capabilities: {drop: ["ALL"], ...}
		...
	}
}

#PinnedImage: {
	image: {
		repository: string
		tag:        #Digest
	}
	...
}

#Chain: "chain-basic" | "chain-country-whitelist" | "chain-network-internal-whitelist"

// ------------------------------------------------------------------ middleware
// Replaces components/common-middlewares. The namespace is a parameter, so the
// PLACEHOLDER/replacements machinery disappears.

#Middlewares: {
	ns: string
	_m: {apiVersion: "traefik.io/v1alpha1", kind: "Middleware"}
	_basics: [{name: "basic-ratelimit"}, {name: "basic-secure-headers"}, {name: "compress"}]

	out: [
		{_m, metadata: {name: "basic-ratelimit", namespace: ns}, spec: rateLimit: {average: 600, burst: 400}},
		{_m, metadata: {name: "basic-secure-headers", namespace: ns}, spec: headers: {
			accessControlAllowMethods: ["GET", "OPTIONS", "HEAD", "PUT"]
			accessControlMaxAge: 100
			browserXssFilter:    true
			contentTypeNosniff:  true
			customRequestHeaders: "X-Forwarded-Proto": "https"
			customResponseHeaders: server:             ""
			forceSTSHeader: true
			referrerPolicy: "same-origin"
			stsSeconds:     63072000
		}},
		{_m, metadata: {name: "chain-basic", namespace: ns}, spec: chain: middlewares: _basics},
		{_m, metadata: {name: "chain-country-whitelist", namespace: ns}, spec: chain: middlewares: list.Concat([[{name: "country-whitelist"}], _basics])},
		{_m, metadata: {name: "chain-network-internal-whitelist", namespace: ns}, spec: chain: middlewares: list.Concat([[{name: "network-internal-whitelist"}], _basics])},
		{_m, metadata: {name: "compress", namespace: ns}, spec: compress: {}},
		{_m, metadata: {name: "country-whitelist", namespace: ns}, spec: plugin: geoblock: {
			allowLocalRequests:    true
			allowUnknownCountries: false
			allowedIPAddresses: ["100.0.0.0/8", "fd7a:115c:a1e0::/48"]
			api:           "https://get.geojs.io/v1/ip/country/{ip}"
			apiTimeoutMs:  500
			blackListMode: false
			cacheSize:     25
			countries: ["CH", "DK", "FR"]
			forceMonthlyUpdate:        true
			logAllowedRequests:        false
			logApiRequests:            false
			logLocalRequests:          false
			silentStartUp:             true
			unknownCountryApiResponse: "nil"
		}},
		{_m, metadata: {name: "network-internal-whitelist", namespace: ns}, spec: ipAllowList: {
			ipStrategy: depth: 0
			sourceRange: ["192.168.1.0/23", "fe80::/10", "100.0.0.0/8", "fd7a:115c:a1e0::/48", "10.244.0.0/16"]
		}},
	]
}

// -------------------------------------------------------------------- volsync
// Replaces ~45 lines of copy-pasted rawResources per backed-up volume.

#VolsyncRestic: {
	app: string, vol: string, size: string
	uid: int, gid:    int

	// gotify's data volume is ReadWriteMany; every other backed-up volume is RWO.
	accessMode: string | *"ReadWriteOnce"

	// The SOPS manifest holding this repository's credential Secret. Required:
	// volsync cannot back up without it, and nothing notices until a run fails.
	secretFile: string

	// The Secret `repository` resolves against; #Bundle collects it.
	secretName: "\(app)-restic-\(vol)"

	_mover: {runAsUser: uid, runAsGroup: gid, fsGroup: gid}

	out: {
		"dest-\(vol)": {
			apiVersion: "volsync.backube/v1alpha1"
			kind:       "ReplicationDestination"
			enabled:    false // restore is deliberate; see the runbook
			spec: spec: {
				trigger: manual: "restore-once"
				restic: {
					repository: secretName
					accessModes: [accessMode]
					capacity:                size
					copyMethod:              "Snapshot"
					moverSecurityContext:    _mover
					storageClassName:        "longhorn"
					volumeSnapshotClassName: "longhorn"
				}
			}
		}
		"source-\(vol)": {
			apiVersion: "volsync.backube/v1alpha1"
			kind:       "ReplicationSource"
			enabled:    true
			spec: spec: {
				sourcePVC: "\(app)-\(vol)"
				trigger: schedule: "@daily"
				restic: {
					repository:        secretName
					pruneIntervalDays: 7
					retain: {daily: 7, weekly: 4}
					copyMethod:            "Clone"
					storageClassName:      "longhorn-local-lax"
					cacheStorageClassName: "longhorn"
					moverSecurityContext:  _mover
				}
			}
		}
	}
}

// ----------------------------------------------------------------- config maps
// Replaces configMapGenerator together with the nameReference `configurations`
// hack each user carries: the name is stable, so nothing has to chase a content
// hash into spec.values.

#ConfigMapFiles: {
	name: string
	ns:   string
	files: [string]: string

	// Grafana's sidecar discovers dashboards by label, so a ConfigMap can need
	// them even though the namespace and name are already fixed.
	labels: [string]: string

	out: {
		apiVersion: "v1"
		kind:       "ConfigMap"
		metadata: {
			"name":    name
			namespace: ns
			if len(labels) > 0 {"labels": labels}
		}
		data: files
	}
}

// ------------------------------------------------------------ namespace certs
// Replaces components/namespace-cert together with its kanidm-specific twin,
// which differed only by a hardcoded `namespace:` working around
// kustomize#5953. The namespace is a parameter, so there is nothing to duplicate.

#NamespaceCert: {
	ns: string

	out: {
		apiVersion: "cert-manager.io/v1"
		kind:       "Certificate"
		metadata: {name: "wildcard-\(ns)", namespace: ns}
		spec: {
			dnsNames: ["*.\(ns).svc.cluster.local", "*.\(ns)"]
			issuerRef: {
				group: "cert-manager.io"
				kind:  "ClusterIssuer"
				name:  "nyx-intermediate-ca"
			}
			secretName: "wildcard-\(ns)-cert"
		}
	}
}

// ------------------------------------------------------------------ scheduling
// `mother` carries `vonarx.online/reserved=storage:NoSchedule`, keeping its
// capacity for ZFS and NFS. Infrastructure that has to cover every node tolerates
// the key whatever a node is reserved for; a workload deliberately placed there
// matches the value, so `grep` finds every such placement.

#Reserved: {
	key:    "vonarx.online/reserved"
	value:  "storage"
	effect: "NoSchedule"

	any: {"key": key, operator: "Exists", "effect": effect}
	storage: {"key": key, operator: "Equal", "value": value, "effect": effect}

	// longhorn configures its system-managed components with a taint string
	// rather than a pod-spec toleration
	taint: "\(key)=\(value):\(effect)"
}

// ------------------------------------------------------------------ media data
// The NFS export every media workload reads, in one place because the address
// moves with the host. Open, so a workload can add its own mounts.

#MediaData: {
	type:   "nfs"
	server: "192.168.0.24"
	path:   "/mnt/chronos/media-data"
	...
}
