package gotify

// cSpell:ignore ALLOWORIGINS druggeri KEEPALIVEPERIODSECONDS LISTENADDR PINGPERIODSECONDS PLUGINSDIR trixie TRUSTEDPROXIES UPLOADEDIMAGESDIR

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "gotify"
	source:    "infrastructure/base/gotify"
	dependsOn: ["kube-prometheus-stack"]
	extraSecretFiles: ["infrastructure/observability/gotify/secrets/gotify.secret.yaml"]
	releases: [_gotify, _bridge]
}

let uid = 568
let gid = 568

// Every pod in this namespace runs as the same unprivileged user.
let podOptions = {
	securityContext: {
		runAsUser:           uid
		runAsGroup:          gid
		runAsNonRoot:        true
		fsGroup:             gid
		fsGroupChangePolicy: "OnRootMismatch"
		seccompProfile: type: "RuntimeDefault"
	}
}

_gotify: schema.#AppRelease & {
	name:      "gotify"
	namespace: bundle.namespace

	let portHTTP = 8080
	let dataSize = "1Gi"
	host: "gotify.vonarx.online"

	let probe = {
		custom:  true
		enabled: true
		spec: httpGet: {path: "/health", port: portHTTP}
	}

	_backup: schema.#VolsyncRestic & {
		app:        name
		vol:        "data"
		size:       dataSize
		"uid":      uid
		"gid":      gid
		accessMode: "ReadWriteMany"
		secretFile: "infrastructure/observability/gotify/secrets/restic.secret.yaml"
	}
	backups: [_backup]

	values: {
		defaultPodOptions: podOptions

		controllers: gotify: {
			type: "deployment"
			containers: gotify: schema.#Hardened & {
				image: {
					repository: "ghcr.io/joker9944/gotify-custom"
					tag:        "3.0.0@sha256:0b51362743f8b88153426be6b1ac0595b2ddc33b7a0798fcb417953df9d7c8ef"
				}
				env: {
					GOTIFY_SERVER_PORT:                     portHTTP
					GOTIFY_SERVER_KEEPALIVEPERIODSECONDS:   0
					GOTIFY_SERVER_LISTENADDR:               null
					GOTIFY_SERVER_SSL_ENABLED:              false
					GOTIFY_SERVER_TRUSTEDPROXIES:           "[10.244.0.0/16]"
					GOTIFY_SERVER_CORS_ALLOWORIGINS:        "[gotify.vonarx.online]"
					GOTIFY_SERVER_STREAM_PINGPERIODSECONDS: 45
					GOTIFY_DATABASE_DIALECT:                "postgres"
					GOTIFY_UPLOADEDIMAGESDIR:               "/data/images"
					GOTIFY_PLUGINSDIR:                      "/plugins"
				}
				envFrom: [
					{secretRef: name: "gotify-default-user"},
					{secretRef: name: "gotify-custom-cnpg-connection"},
				]
				probes: {
					liveness: probe & {spec: failureThreshold: 6}
					readiness: probe
					startup: probe & {spec: {failureThreshold: 30, periodSeconds: 5}}
				}
				resources: {
					requests: {cpu: "50m", memory: "1Gi"}
					limits: memory: "2Gi"
				}
			}

			// blocks startup until the CNPG cluster below is accepting connections
			initContainers: postgresql: schema.#Hardened & {
				image: {
					repository: "ghcr.io/joker9944/postgresql-client"
					tag:        "4.0.0@sha256:af64249920494097d4185d8c2327b209014c28458295372222804a7a087842c6"
				}
				env: {
					PGHOST: "gotify-cnpg-rw"
					PGUSER: valueFrom: secretKeyRef: {name: "gotify-custom-cnpg-user", key: "username"}
					PGPASSWORD: valueFrom: secretKeyRef: {name: "gotify-custom-cnpg-user", key: "password"}
					PGDATABASE: "gotify"
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

		service: gotify: {
			controller: "gotify"
			primary:    true
			ports: http: {primary: true, port: 80, targetPort: portHTTP}
		}

		ingress: gotify: {
			hosts: [{
				"host": host
				paths: [{path: "/", service: {identifier: "gotify", port: "http"}}]
			}]
			tls: [{hosts: [host], secretName: "wildcard-vonarx-online-cert"}]
		}

		persistence: data: {
			type:       "persistentVolumeClaim"
			accessMode: "ReadWriteMany"
			retain:     true
			size:       dataSize
			dataSourceRef: {apiGroup: "volsync.backube", kind: "ReplicationDestination", "name": "\(name)-dest-data"}
		}

		rawResources: cnpg: {
			apiVersion: "postgresql.cnpg.io/v1"
			kind:       "Cluster"
			spec: spec: {
				description: "PostgreSQL Cluster for gotify"
				instances:   3

				imageCatalogRef: {
					apiGroup: "postgresql.cnpg.io"
					kind:     "ClusterImageCatalog"
					"name":   "postgresql-standard-trixie"
					major:    18
				}

				storage: {size: "1Gi", storageClass: "longhorn-local-strict"}
				walStorage: {size: "1Gi", storageClass: "longhorn-local-strict"}

				bootstrap: initdb: {
					database: "gotify"
					owner:    "gotify"
					secret: name: "gotify-custom-cnpg-user"
				}

				affinity: {
					enablePodAntiAffinity: true
					podAntiAffinityType:   "required"
				}
			}
		}
	}
}

// Turns Alertmanager webhooks into Gotify messages; kube-prometheus-stack's
// alertmanager posts to its Service.
_bridge: schema.#AppRelease & {
	name:      "gotify-alertmanager-bridge"
	namespace: bundle.namespace

	let portHTTP = 8080

	values: {
		defaultPodOptions: podOptions

		controllers: "gotify-alertmanager-bridge": {
			type: "deployment"
			containers: bridge: schema.#Hardened & {
				image: {
					repository: "ghcr.io/druggeri/alertmanager_gotify_bridge"
					tag:        "2.3.2@sha256:242441023c6a7956fc7bcdd30350a8fed38f791e703d670aa286fc0465f88b41"
				}
				env: {
					GOTIFY_ENDPOINT:     "http://gotify/message"
					PORT:                portHTTP
					WEBHOOK_PATH:        "/webhook"
					PRIORITY_ANNOTATION: "severity"
				}
				envFrom: [{secretRef: name: "gotify-alertmanager-bridge-default-token"}]
				probes: {
					liveness: {enabled: true, port: portHTTP, spec: failureThreshold: 6}
					readiness: {enabled: true, port: portHTTP}
					startup: {enabled: true, port: portHTTP, spec: {failureThreshold: 30, periodSeconds: 5}}
				}
				resources: {
					requests: {cpu: "50m", memory: "1Gi"}
					limits: memory: "2Gi"
				}
			}
		}

		service: "gotify-alertmanager-bridge": {
			controller: "gotify-alertmanager-bridge"
			primary:    true
			ports: http: {primary: true, port: 80, targetPort: portHTTP}
		}
	}
}
