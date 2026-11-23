package valheim

// cSpell:ignore permittedlist PGID

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "valheim"
	// supervisord starts as root and drops to PUID; every capability it adds
	// back is within baseline
	namespaceLabels: "pod-security.kubernetes.io/enforce": "baseline"
	middlewares: false
	extraSecretFiles: ["apps/valheim/secrets/valheim.secret.yaml"]
	releases: [_valheim]
}

_valheim: schema.#AppRelease & {
	name:      "valheim"
	namespace: "valheim"

	let uid = 6020
	let gid = 6020

	let configSize = "5Gi"
	let listsDir = "/etc/valheim-lists"

	_backup: schema.#VolsyncRestic & {
		app:        name, vol:  "config", size: configSize
		"uid":      uid, "gid": gid
		secretFile: "apps/valheim/secrets/restic.secret.yaml"
	}
	backups: [_backup]

	values: {
		controllers: valheim: {
			type: "statefulset"
			pod: securityContext: {
				runAsUser:           0
				runAsGroup:          0
				runAsNonRoot:        false
				fsGroup:             gid
				fsGroupChangePolicy: "OnRootMismatch"
				seccompProfile: type: "RuntimeDefault"
			}
			containers: valheim: schema.#HardenedWritableRoot & {
				image: {
					repository: "ghcr.io/community-valheim-tools/valheim-server"
					tag:        "1.4.1@sha256:f34d67ba8023e343b10ffda0144759a8c8d986f276510460315a01051bed8a6d"
				}
				securityContext: capabilities: add: ["CHOWN", "DAC_OVERRIDE", "FOWNER", "KILL", "SETGID", "SETUID"]
				env: {
					TZ:          "Europe/Zurich"
					PUID:        uid
					PGID:        gid
					SERVER_NAME: "nyx"
					WORLD_NAME:  "wir"
					SERVER_PASS: valueFrom: secretKeyRef: {name: "valheim", key: "SERVER_PASS"}
					// a Steam listing would advertise the CGNAT egress address
					SERVER_PUBLIC: "false"
					// volsync backs up /config
					BACKUPS:             "false"
					PRE_SUPERVISOR_HOOK: "cp \(listsDir)/permittedlist.txt /config/permittedlist.txt"
				}
				resources: {
					requests: {cpu: "2", memory: "4Gi"}
					limits: memory: "6Gi"
				}
			}
		}

		// Reached by the edge's nginx over the WireGuard tunnel, bypassing
		// Traefik. Cluster rather than Local: nginx cannot health-check UDP, so
		// every spoke has to forward to wherever the pod runs.
		service: valheim: {
			controller:            "valheim"
			type:                  "NodePort"
			externalTrafficPolicy: "Cluster"
			ports: {
				game: {port: 2456, protocol: "UDP", nodePort: schema.#EdgeUDPNodePorts.valheim."2456"}
				query: {port: 2457, protocol: "UDP", nodePort: schema.#EdgeUDPNodePorts.valheim."2457"}
			}
		}

		persistence: {
			// No dataSourceRef: a new claim bound through a disabled destination
			// stays Pending. A restore recreates the claim with one.
			config: {
				type:       "persistentVolumeClaim"
				accessMode: "ReadWriteOnce"
				retain:     true
				size:       configSize
			}
			// SteamCMD's install; re-downloaded if lost, so not backed up
			server: {
				type:       "persistentVolumeClaim"
				accessMode: "ReadWriteOnce"
				size:       "5Gi"
				globalMounts: [{path: "/opt/valheim"}]
			}
			// Steam IDs, one per line; an empty list admits everyone. In the
			// secret because the repo is public.
			lists: {
				type: "secret"
				name: "valheim"
				items: [{key: "permittedlist.txt", path: "permittedlist.txt"}]
				globalMounts: [{path: listsDir}]
			}
		}
	}
}
