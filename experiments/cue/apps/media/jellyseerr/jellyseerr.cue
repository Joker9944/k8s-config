package jellyseerr

// cSpell:ignore fallenbagel

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "jellyseerr"
	source:    "apps/base/jellyseerr"
	secretFiles: ["apps/media/jellyseerr/secrets/values.secret.yaml"]
	releases: [_jellyseerr]
}

_jellyseerr: schema.#AppRelease & {
	name:      "jellyseerr"
	namespace: "jellyseerr"

	secretValuesName: "jellyseerr-secret-values"

	let uid = 568
	let gid = 568
	let portHTTP = 5055
	host: "jellyseerr.vonarx.online"

	let configSize = "1Gi"

	// jellyseerr is scheduled and labelled with the servarr stack it fronts
	let partOf = "servarr"

	_backup: schema.#VolsyncRestic & {
		app:   name, vol:  "config", size: configSize
		"uid": uid, "gid": gid
	}

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
					repository: "fallenbagel/jellyseerr"
					tag:        "2.7.3@sha256:4538137bc5af902dece165f2bf73776d9cf4eafb6dd714670724af8f3eb77764"
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
			yarn: {type: "emptyDir", globalMounts: [{path: "/.yarn"}]}
			tmp: type: "emptyDir"
		}

		rawResources: _backup.out
	}
}
