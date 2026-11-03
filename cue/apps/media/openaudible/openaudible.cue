package openaudible

// cSpell:ignore lanjelin

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "openaudible"
	// the only ingress here is served from the tailnet, so no Traefik middleware
	middlewares: false
	releases: [_openaudible]
}

_openaudible: schema.#AppRelease & {
	name:      "openaudible"
	namespace: "openaudible"

	let uid = 6012
	let gid = 6000
	let portHTTP = 3000
	host:    "openaudible.\(schema.#TailnetDomain)"
	tailnet: true

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
					tag:        "4.8.8@sha256:3736ff851754d9017db02cebd3445d7b10e733fae149df1cbbd7af9068ed3f95"
				}
				securityContext: capabilities: add: ["CHOWN", "SETUID", "SETGID", "FOWNER", "DAC_OVERRIDE"]
				env: {
					CUSTOM_PORT: portHTTP
					UMASK:       "0002"
					PUID:        uid
					PGID:        gid
					// Xvfb's framebuffer is a SysV shm segment charged to the pod cgroup;
					// the image's 15360x8640 default reserves 506Mi of the memory limit
					MAX_RES: "1920x1080"
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
			// tailscale provisions and serves the certificate; no Secret is involved
			tls: [{hosts: [host]}]
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
