package audiobookshelf

// cSpell:ignore advplyr

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "audiobookshelf"
	releases: [_audiobookshelf]
}

_audiobookshelf: schema.#AppRelease & {
	name:      "audiobookshelf"
	namespace: "audiobookshelf"

	let uid = 6011
	let gid = 6000
	let portHTTP = 8080
	let pathConfig = "/config"
	let pathMetadata = "/metadata"
	host: "audiobookshelf.vonarx.online"

	let configSize = "1Gi"
	let metadataSize = "1Gi"

	let probe = {
		custom:  true
		enabled: true
	}

	let secretFile = "apps/media/audiobookshelf/secrets/restic.secret.yaml"
	_backupConfig: schema.#VolsyncRestic & {
		app:          name, vol:  "config", size: configSize
		"uid":        uid, "gid": gid
		"secretFile": secretFile
	}
	_backupMetadata: schema.#VolsyncRestic & {
		app:          name, vol:  "metadata", size: metadataSize
		"uid":        uid, "gid": gid
		"secretFile": secretFile
	}
	backups: [_backupConfig, _backupMetadata]

	values: {
		controllers: audiobookshelf: {
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
			containers: audiobookshelf: schema.#Hardened & {
				image: {
					repository: "advplyr/audiobookshelf"
					tag:        "2.35.1@sha256:1eef6716183c52abafe5405e7d6be8390248ecd59c7488c44af871757ac8fc4d"
				}
				env: {
					UMASK:         "0002"
					PORT:          portHTTP
					CONFIG_PATH:   pathConfig
					METADATA_PATH: pathMetadata
				}
				probes: {
					liveness: probe & {spec: {httpGet: {path: "/healthcheck", port: portHTTP}, failureThreshold: 6}}
					readiness: probe & {spec: httpGet: {path: "/ping", port: portHTTP}}
					startup: probe & {spec: {httpGet: {path: "/healthcheck", port: portHTTP}, failureThreshold: 30, periodSeconds: 5}}
				}
				resources: {
					requests: {cpu: "30m", memory: "200Mi"}
					limits: memory: "500Mi"
				}
			}
		}

		service: audiobookshelf: {
			controller: "audiobookshelf"
			ports: http: port: portHTTP
		}

		ingress: audiobookshelf: {
			hosts: [{"host": host, paths: [{path: "/", service: {identifier: "audiobookshelf", port: "http"}}]}]
			tls: [{hosts: [host], secretName: "wildcard-vonarx-online-cert"}]
		}

		persistence: {
			config: {
				type:       "persistentVolumeClaim"
				accessMode: "ReadWriteOnce"
				retain:     true
				size:       configSize
				globalMounts: [{path: pathConfig}]
				dataSourceRef: {apiGroup: "volsync.backube", kind: "ReplicationDestination", "name": "\(name)-dest-config"}
			}
			metadata: {
				type:       "persistentVolumeClaim"
				accessMode: "ReadWriteOnce"
				retain:     true
				size:       metadataSize
				globalMounts: [{path: pathMetadata}]
				dataSourceRef: {apiGroup: "volsync.backube", kind: "ReplicationDestination", "name": "\(name)-dest-metadata"}
			}
			media: schema.#MediaData & {
				globalMounts: [{path: "/audiobooks"}]
			}
			tmp: type: "emptyDir"
		}
	}
}
