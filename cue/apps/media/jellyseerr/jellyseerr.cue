package jellyseerr

// The product is seerr upstream; every name here is still jellyseerr.
// /decisions/jellyseerr-is-now-seerr.md says why.

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "jellyseerr"
	releases: [_jellyseerr]
}

_jellyseerr: schema.#AppRelease & {
	name:      "jellyseerr"
	namespace: "jellyseerr"

	let uid = 568
	let gid = 568
	let portHTTP = 5055
	host: "jellyseerr.vonarx.online"

	let configSize = "1Gi"

	// jellyseerr is scheduled and labelled with the servarr stack it fronts
	let partOf = "servarr"

	_backup: schema.#VolsyncRestic & {
		app:        name, vol:  "config", size: configSize
		"uid":      uid, "gid": gid
		secretFile: "apps/media/jellyseerr/secrets/restic.secret.yaml"
	}
	backups: [_backup]

	values: {
		global: labels: "app.kubernetes.io/part-of": partOf

		defaultPodOptions: {
			labels: "app.kubernetes.io/part-of": partOf
			topologySpreadConstraints: [{
				maxSkew:           1
				topologyKey:       "kubernetes.io/hostname"
				whenUnsatisfiable: "ScheduleAnyway"
				labelSelector: matchLabels: "app.kubernetes.io/part-of": partOf
			}]
		}

		controllers: jellyseerr: {
			type: "statefulset"
			pod: securityContext: {
				runAsUser:           uid
				runAsGroup:          gid
				runAsNonRoot:        true
				fsGroup:             gid
				fsGroupChangePolicy: "OnRootMismatch"
				seccompProfile: type: "RuntimeDefault"
			}
			containers: jellyseerr: schema.#Hardened & {
				image: {
					repository: "ghcr.io/seerr-team/seerr"
					tag:        "v3.0.1@sha256:1b5fc1ea825631d9d165364472663b817a4c58ef6aa1013f58d82c1570d7c866"
				}
				env: {
					PORT:      portHTTP
					LOG_LEVEL: "INFO"
				}
				probes: {
					liveness: {enabled: true, spec: failureThreshold: 6}
					readiness: enabled: true
					startup: {enabled: true, spec: {failureThreshold: 30, periodSeconds: 5}}
				}
				resources: {
					requests: {cpu: "30m", memory: "1Gi"}
					limits: memory: "2Gi"
				}
			}
		}

		service: jellyseerr: {
			controller: "jellyseerr"
			ports: http: port: portHTTP
		}

		ingress: jellyseerr: {
			hosts: [{"host": host, paths: [{path: "/", service: {identifier: "jellyseerr", port: "http"}}]}]
			tls: [{hosts: [host], secretName: "wildcard-vonarx-online-cert"}]
		}

		persistence: {
			config: {
				type:       "persistentVolumeClaim"
				accessMode: "ReadWriteOnce"
				retain:     true
				size:       configSize
				dataSourceRef: {apiGroup: "volsync.backube", kind: "ReplicationDestination", "name": "\(name)-dest-config"}
				globalMounts: [{path: "/app/config"}]
			}
			cache: {type: "emptyDir", globalMounts: [{path: "/.cache"}]}
			tmp: type: "emptyDir"
		}
	}
}
