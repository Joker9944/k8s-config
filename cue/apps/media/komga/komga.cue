@extern(embed)

package komga

// cSpell:ignore ACCOUNTCREATION ALLOWEDORIGINS CLIENTSECRET gotson OIDCEMAILVERIFICATION SPRINGFRAMEWORK

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "komga"
	extraSecretFiles: ["apps/media/komga/secrets/komga.secret.yaml"]
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
		app:        name, vol:  "config", size: configSize
		"uid":      uid, "gid": gid
		secretFile: "apps/media/komga/secrets/restic.secret.yaml"
	}
	backups: [_backup]

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
			}
			// TODO Probes
			// TODO Resources
			containers: komga: schema.#Hardened & {
				image: {
					repository: "gotson/komga"
					tag:        "1.26.3@sha256:6c2a967bbe9acefd05933b2eb498f34afe96a83c6f7f8ab0acb512a1bb3ab50f"
				}
				env: {
					UMASK:                       "0002"
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
				dataSourceRef: {apiGroup: "volsync.backube", kind: "ReplicationDestination", "name": "\(name)-dest-config"}
			}
			"config-overlay": {
				type: "configMap"
				name: _configOverlay.name
				globalMounts: [{path: "/config/application.yml", subPath: "application.yml"}]
			}
			data: schema.#MediaData
			tmp: type: "emptyDir"
		}
	}
}
