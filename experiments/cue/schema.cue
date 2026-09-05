package nyx

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

#HardenedBase: {
	securityContext: {
		allowPrivilegeEscalation: false
		capabilities: drop: ["ALL"]
		...
	}
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
	_mover: {runAsUser: uid, runAsGroup: gid, fsGroup: gid}
	_repo: "\(app)-restic-\(vol)"

	out: {
		"dest-\(vol)": {
			apiVersion: "volsync.backube/v1alpha1"
			kind:       "ReplicationDestination"
			enabled:    false // restore is deliberate; see the runbook
			spec: spec: {
				trigger: manual: "restore-once"
				restic: {
					repository: _repo
					accessModes: ["ReadWriteOnce"]
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
					repository:        _repo
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
