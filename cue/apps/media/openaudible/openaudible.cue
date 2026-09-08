package openaudible

// cSpell:ignore lanjelin

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "openaudible"
	releases: [_openaudible]
}

_openaudible: schema.#AppRelease & {
	name:      "openaudible"
	namespace: "openaudible"

	let uid = 6012
	let gid = 6000
	let portHTTP = 3000
	host:  "openaudible.vonarx.online"
	chain: "chain-network-internal-whitelist"

	let configSize = "500Mi"

	// the selkies service is the only reliable liveness signal this image gives
	let probe = {
		custom:  true
		enabled: true
		spec: exec: command: [
			"/bin/sh", "-c",
			"/usr/bin/s6-svstat -o up /run/service/svc-selkies | grep --quiet true",
		]
	}

	_backup: schema.#VolsyncRestic & {
		app:        name, vol:  "config", size: configSize
		"uid":      uid, "gid": gid
		secretFile: "apps/media/openaudible/secrets/restic.secret.yaml"
	}
	backups: [_backup]

	values: {
		controllers: openaudible: {
			type: "statefulset"
			pod: {
				securityContext: {
					runAsNonRoot:        false
					fsGroup:             gid
					fsGroupChangePolicy: "OnRootMismatch"
					supplementalGroups: [568]
					seccompProfile: type: "RuntimeDefault"
				}
				nodeSelector: "kubernetes.io/arch": "amd64"
			}
			containers: openaudible: schema.#HardenedWritableRoot & {
				image: {
					repository: "ghcr.io/lanjelin/openaudible-docker"
					tag:        "4.8.7@sha256:9096572063e7294634f2fa3a11a138952eb394c4a08abadd33b26440b77151ab"
				}
				securityContext: capabilities: add: ["CHOWN", "SETUID", "SETGID", "FOWNER", "DAC_OVERRIDE"]
				env: {
					CUSTOM_PORT: portHTTP
					UMASK:       "0002"
					PUID:        uid
					PGID:        gid
				}
				probes: {
					liveness: probe & {spec: failureThreshold: 6}
					readiness: probe
					startup: probe & {spec: {failureThreshold: 30, periodSeconds: 5}}
				}
				resources: {
					requests: {cpu: "70m", memory: "700Mi"}
					limits: memory: "1Gi"
				}
			}
		}

		service: openaudible: {
			controller: "openaudible"
			ports: http: port: portHTTP
		}

		ingress: openaudible: {
			hosts: [{"host": host, paths: [{path: "/", service: {identifier: "openaudible", port: "http"}}]}]
			tls: [{hosts: [host], secretName: "wildcard-vonarx-online-cert"}]
		}

		persistence: {
			config: {
				type:       "persistentVolumeClaim"
				accessMode: "ReadWriteOnce"
				retain:     true
				size:       configSize
				dataSourceRef: {apiGroup: "volsync.backube", kind: "ReplicationDestination", "name": "\(name)-dest-config"}
				globalMounts: [{path: "/config/OpenAudible"}]
			}
			media: schema.#MediaData & {
				globalMounts: [{path: "/mnt/media-data"}]
			}
			cache: {type: "emptyDir", globalMounts: [{path: "/config/.cache"}]}
			tmp: type: "emptyDir"
		}
	}
}
