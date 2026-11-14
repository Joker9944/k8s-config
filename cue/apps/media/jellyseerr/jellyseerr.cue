@extern(embed)

package jellyseerr

// The product is seerr upstream; every name here is still jellyseerr.
// /decisions/jellyseerr-is-now-seerr.md says why.

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "jellyseerr"
	before: [_logs.out]
	releases: [_jellyseerr]
}

_jellyseerrLogs: _ @embed(file="files/jellyseerr.alloy", type=text)

_logs: schema.#AlloyPipeline & {
	app:    "jellyseerr"
	ns:     bundle.namespace
	config: _jellyseerrLogs
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
			labels: _logs.podLabels
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
					tag:        "v3.5.2@sha256:aadee014b40e28cf9aa4928bc9d1183a6eb08f8c44d543cddc9efdcb16549be2"
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
