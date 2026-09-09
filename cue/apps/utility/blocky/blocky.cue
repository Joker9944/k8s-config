@extern(embed)

package blocky

// cSpell:ignore xerr

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "blocky"
	// DNS is served on a LoadBalancer, so there is no ingress to protect
	middlewares: false
	repositories: [
		schema.#HelmRepo & {name: "bjw-s", url: "https://bjw-s-labs.github.io/helm-charts"},
		schema.#HelmRepo & {name: "ot-helm", url: "https://ot-container-kit.github.io/helm-charts", interval: "30m"},
	]
	before: [_configTemplates.out]
	releases: [_blocky, _redis]
}

// Plaintext config, read from disk at evaluation time. @embed cannot escape the
// package directory, which is why this file lives here. jinja renders it into
// the real config at startup, which is why it is a template and not the config.
_configYml: _ @embed(file="files/config.yml", type=text)

_configTemplates: schema.#ConfigMapFiles & {
	name: "blocky-config-templates"
	ns:   "blocky"
	files: "config.yml": _configYml
}

_redis: schema.#Release & {
	name:      "blocky-redis"
	namespace: "blocky"
	chart:     "redis"
	// renovate: datasource=helm packageName=redis registryUrl=https://ot-container-kit.github.io/helm-charts
	version:    "0.16.9"
	sourceName: "ot-helm"
	hasValues:  false
}

_blocky: schema.#AppRelease & {
	name:      "blocky"
	namespace: "blocky"

	let uid = 568
	let gid = 568
	let cnpgSecret = "blocky-cnpg-app"

	let probe = {
		custom:  true
		enabled: true
		spec: {
			exec: command: ["/app/blocky", "healthcheck"]
			timeoutSeconds: 3
		}
	}

	values: {
		defaultPodOptions: securityContext: {
			runAsUser:           uid
			runAsGroup:          gid
			runAsNonRoot:        true
			fsGroup:             gid
			fsGroupChangePolicy: "OnRootMismatch"
			seccompProfile: type: "RuntimeDefault"
		}

		controllers: blocky: {
			type:     "deployment"
			replicas: 2
			strategy: "RollingUpdate"

			containers: blocky: schema.#Hardened & {
				image: {
					repository: "ghcr.io/0xerr0r/blocky"
					tag:        "v0.26@sha256:b259ada3f943e73283f1fc5e84ac39a791afec7de86515d1aeccc03d2c39e595"
				}
				probes: {
					liveness: probe & {spec: failureThreshold: 6}
					readiness: probe
					// the first run downloads every block list: 120 * 5s = 10m
					startup: probe & {spec: {failureThreshold: 120, periodSeconds: 5}}
				}
				resources: {
					requests: {cpu: "30m", memory: "100Mi"}
					limits: memory: "500Mi"
				}
				args: ["--config", "/config/"]
				securityContext: capabilities: add: ["NET_BIND_SERVICE"]
			}

			initContainers: {
				jinja: schema.#Hardened & {
					image: {
						repository: "ghcr.io/joker9944/jinja-cli"
						tag:        "4.0.0@sha256:81cd8cd0daa0baab6b1994d6b0c14c88ba812faa5c740f3637295f31b8f20479"
					}
					env: {
						PGURI: valueFrom: secretKeyRef: {name: cnpgSecret, key: "uri"}
						KUBERNETES_NAMESPACE: valueFrom: fieldRef: fieldPath: "metadata.namespace"
					}
					command: ["/bin/sh", "-c"]
					args: ["jinja2 /templates/config.yml > /config/config.yml"]
				}

				postgresql: schema.#Hardened & {
					image: {
						repository: "ghcr.io/joker9944/postgresql-client"
						tag:        "4.0.0@sha256:e8143037a7aff99758c35b2f35a76bf290ccd6cbaded614de793e8a1a2496f8d"
					}
					env: {
						PGHOST: valueFrom: secretKeyRef: {name: cnpgSecret, key: "host"}
						PGUSER: valueFrom: secretKeyRef: {name: cnpgSecret, key: "user"}
						PGPASSWORD: valueFrom: secretKeyRef: {name: cnpgSecret, key: "password"}
						PGDATABASE: valueFrom: secretKeyRef: {name: cnpgSecret, key: "dbname"}
					}
					command: ["/bin/sh", "-c"]
					args: ["""
						echo "Testing connection for DB $PGDATABASE on $PGHOST"
						until
						  pg_isready
						  do sleep 5
						done
						echo "DB $PGDATABASE available on $PGHOST"

						"""]
				}
			}
		}

		service: {
			dns: {
				controller: "blocky"
				type:       "LoadBalancer"
				annotations: "metallb.io/loadBalancerIPs": "192.168.0.129"
				ports: {
					"dns-tcp": {port: 53, protocol: "TCP"}
					"dns-udp": {port: 53, protocol: "UDP"}
				}
			}
			// TODO Implement DoT with IngressRouteTCP, issue with conditional
			// mapping when accessing from WAN
			dot: {
				controller: "blocky"
				ports: dot: {port: 853, protocol: "TCP"}
			}
			metrics: {
				controller: "blocky"
				ports: http: port: 4000
			}
		}

		persistence: {
			config: type: "emptyDir"
			templates: {
				type: "configMap"
				name: _configTemplates.name
				advancedMounts: blocky: jinja: [{path: "/templates"}]
			}
		}

		rawResources: cnpg: {
			apiVersion: "postgresql.cnpg.io/v1"
			kind:       "Cluster"
			spec: spec: {
				description: "PostgreSQL Cluster for blocky"
				instances:   3
				imageCatalogRef: {
					apiGroup: "postgresql.cnpg.io"
					kind:     "ClusterImageCatalog"
					name:     "postgresql-standard-trixie"
					major:    17
				}
				storage: {size: "1Gi", storageClass: "longhorn-local-strict"}
				walStorage: {size: "1Gi", storageClass: "longhorn-local-strict"}
				bootstrap: initdb: {database: "query-log", owner: "blocky"}
				affinity: {enablePodAntiAffinity: true, podAntiAffinityType: "required"}
			}
		}
	}
}
