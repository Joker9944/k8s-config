package attic

// cSpell:ignore atticd rwc

import (
	"encoding/toml"

	"github.com/joker9944/k8s-config/schema"
)

bundle: schema.#Bundle & {
	namespace: "attic"
	needs: ["object-storage"]
	// the only ingress here is served from the tailnet, so no Traefik middleware
	middlewares: false
	extraSecretFiles: ["apps/dev/attic/secrets/attic.secret.yaml"]
	before: [_config.out]
	releases: [_attic]
}

let portHTTP = 8080

// The JWT signing key and the S3 credentials are read from the environment,
// so the config holds no secrets.
_config: schema.#ConfigMapFiles & {
	name: "attic-config"
	ns:   bundle.namespace
	files: "server.toml": toml.Marshal({
		listen:         "0.0.0.0:\(portHTTP)"
		"api-endpoint": "https://\(_attic.host)/"
		database: url: "sqlite:///data/server.db?mode=rwc"
		storage: {
			type:     "s3"
			region:   "nyx"
			bucket:   "attic"
			endpoint: "http://garage.garage.svc.cluster.local:3900"
		}
		// Changing any of these moves the cutpoints, so new NARs stop
		// deduplicating against existing chunks until the old ones age out.
		chunking: {
			"nar-size-threshold": 65536
			"min-size":           16384
			"avg-size":           65536
			"max-size":           262144
		}
		compression: type: "zstd"
		"garbage-collection": {
			interval:                   "12 hours"
			"default-retention-period": "14 days"
		}
	})
}

_attic: schema.#AppRelease & {
	name:      "attic"
	namespace: bundle.namespace

	let uid = 568
	let gid = 568
	let dataSize = "2Gi"

	host:    "attic.\(schema.#TailnetDomain)"
	tailnet: true

	let probe = {
		custom:  true
		enabled: true
		spec: httpGet: {path: "/", port: portHTTP}
	}

	values: {
		controllers: attic: {
			type: "statefulset"
			pod: securityContext: {
				runAsUser:           uid
				runAsGroup:          gid
				runAsNonRoot:        true
				fsGroup:             gid
				fsGroupChangePolicy: "OnRootMismatch"
				seccompProfile: type: "RuntimeDefault"
			}
			containers: attic: schema.#Hardened & {
				image: {
					// upstream publishes no versions; main is the only tag tracking a branch
					repository: "ghcr.io/zhaofengli/attic"
					tag:        "main@sha256:18574aba70fc89d2b695273fbe2e7b2f8ad7e8e786b4cc535124fbe14bada1d0"
				}
				args: ["--config", "/config/server.toml"]
				envFrom: [{secretRef: name: "attic"}]
				probes: {
					liveness: probe & {spec: failureThreshold: 6}
					readiness: probe
					startup: probe & {spec: {failureThreshold: 30, periodSeconds: 5}}
				}
				resources: {
					requests: {cpu: "100m", memory: "256Mi"}
					limits: memory: "2Gi"
				}
			}
		}

		service: attic: {
			controller: "attic"
			ports: http: port: portHTTP
		}

		ingress: attic: {
			hosts: [{"host": host, paths: [{path: "/", service: {identifier: "attic", port: "http"}}]}]
			tls: [{hosts: [host]}]
		}

		persistence: {
			data: {
				type:       "persistentVolumeClaim"
				accessMode: "ReadWriteOnce"
				retain:     true
				size:       dataSize
				dataSourceRef: {apiGroup: "volsync.backube", kind: "ReplicationDestination", "name": "\(name)-dest-data"}
			}
			config: {
				type: "configMap"
				name: _config.name
				globalMounts: [{path: "/config", readOnly: true}]
			}
			tmp: type: "emptyDir"
		}
	}
}
