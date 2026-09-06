@extern(embed)

package komga

// cSpell:ignore ACCOUNTCREATION ALLOWEDORIGINS CLIENTSECRET gotson OIDCEMAILVERIFICATION SPRINGFRAMEWORK

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "komga"
	source:    "apps/base/komga"
	secretFiles: ["apps/media/komga/secrets/komga.secret.yaml"]
	before: [_configOverlay.out]
	releases: [_komga]
}

// Plaintext config, read from disk at evaluation time. @embed cannot escape the
// package directory, which is why this file lives here.
_applicationYml: _ @embed(file="files/application.yml", type=text)

_configOverlay: schema.#ConfigMapFiles & {
	name: "komga-config-overlay"
	ns:   "komga"
	files: "application.yml": _applicationYml
}

_komga: schema.#AppRelease & {
	name:      "komga"
	namespace: "komga"

	let uid = 6013
	let gid = 6000
	let portHTTP = 25600
	host: "komga.vonarx.online"

	let configSize = "1Gi"

	_backup: schema.#VolsyncRestic & {
		app:   name, vol:  "config", size: configSize
		"uid": uid, "gid": gid
	}

	values: {
		controllers: komga: {
			type: "statefulset"
			pod: {
				securityContext: {
					runAsUser:           uid
					runAsGroup:          gid
					runAsNonRoot:        true
					fsGroup:             gid
					fsGroupChangePolicy: "OnRootMismatch"
					supplementalGroups: [568]
					seccompProfile: type: "RuntimeDefault"
				}
				affinity: nodeAffinity: preferredDuringSchedulingIgnoredDuringExecution: [{
					weight: 10
					preference: matchExpressions: [{key: "vonarx.online/nfs-host", operator: "Exists"}]
				}]
			}
			// TODO Probes
			// TODO Resources
			containers: komga: schema.#Hardened & {
				image: {
					repository: "gotson/komga"
					tag:        "1.25.0@sha256:c4f9885fc077e2e9cd684dc95e8f6cfa5e33b100b46712b2de7f5cc2ff59e6fb"
				}
				env: {
					UMASK:                       2
					SERVER_PORT:                 portHTTP
					KOMGA_CORS_ALLOWEDORIGINS:   "https://\(host)"
					KOMGA_OAUTH2ACCOUNTCREATION: "true"
					KOMGA_OIDCEMAILVERIFICATION: "false"
					SPRING_SECURITY_OAUTH2_CLIENT_REGISTRATION_KANIDM_CLIENTSECRET: valueFrom: secretKeyRef: {
						name: "komga-oidc"
						key:  "client-secret"
					}
					LOGGING_LEVEL_ORG_SPRINGFRAMEWORK_SECURITY: "INFO"
				}
			}
		}

		service: komga: {
			controller: "komga"
			ports: http: port: portHTTP
		}

		ingress: komga: {
			hosts: [{"host": host, paths: [{path: "/", service: {identifier: "komga", port: "http"}}]}]
			tls: [{hosts: [host], secretName: "wildcard-vonarx-online-cert"}]
		}

		persistence: {
			config: {
				type:       "persistentVolumeClaim"
				accessMode: "ReadWriteOnce"
				retain:     true
				size:       configSize
			}
			"config-overlay": {
				type: "configMap"
				name: _configOverlay.name
				globalMounts: [{path: "/config/application.yml", subPath: "application.yml"}]
			}
			data: {
				type:   "nfs"
				server: "192.168.0.10"
				path:   "/mnt/chronos/media-data"
			}
		}

		rawResources: _backup.out
	}
}
