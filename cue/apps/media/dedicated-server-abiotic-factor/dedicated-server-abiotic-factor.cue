package dedicatedserverabioticfactor

// cSpell:ignore dedicatedserverabioticfactor

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "dedicated-server-abiotic-factor"
	extraSecretFiles: [
		"apps/media/dedicated-server-abiotic-factor/secrets/dedicated-server-abiotic-factor.secret.yaml",
	]
	// no ingress: the server is reached on its own LoadBalancer
	middlewares: false
	releases: [_server]
}

_server: schema.#AppRelease & {
	name:      "dedicated-server-abiotic-factor"
	namespace: "dedicated-server-abiotic-factor"

	let uid = 1000
	let gid = 1000
	let savedSize = "2Gi"

	// the server is off; bring it up by dropping this
	out: spec: suspend: true

	_backup: schema.#VolsyncRestic & {
		app:        name, vol:  "saved", size: savedSize
		"uid":      uid, "gid": gid
		secretFile: "apps/media/dedicated-server-abiotic-factor/secrets/restic.secret.yaml"
	}
	backups: [_backup]

	values: {
		controllers: (name): {
			type: "statefulset"
			pod: {
				securityContext: {
					runAsNonRoot: true
					runAsUser:    uid
					runAsGroup:   gid
					supplementalGroups: [568]
					fsGroup: gid
					seccompProfile: type: "RuntimeDefault"
				}
				affinity: nodeAffinity: {
					// the server needs a node that can actually hold it
					requiredDuringSchedulingIgnoredDuringExecution: nodeSelectorTerms: [{
						matchExpressions: [
							{key: "vonarx.online/cpu-capacity", operator: "Gt", values: ["5"]},
							{key: "vonarx.online/memory-capacity", operator: "Gt", values: ["10240"]},
						]
					}]
					preferredDuringSchedulingIgnoredDuringExecution: [
						{weight: 10, preference: matchExpressions: [{key: "vonarx.online/cpu-performance", operator: "In", values: ["high"]}]},
						{weight: 10, preference: matchExpressions: [{key: "vonarx.online/memory-performance", operator: "In", values: ["high"]}]},
					]
				}
			}

			containers: (name): schema.#Hardened & {
				image: {
					repository: "ghcr.io/joker9944/abiotic-factor-server"
					tag:        "1.0.3@sha256:a138c5e5fa0dbc702212419f467e7d7c6580dd9a0302083b0f19b9f49778991e"
				}
				envFrom: [{secretRef: "name": name}]
				// requests = limits for Guaranteed QoS
				resources: {
					requests: {cpu: 4, memory: "4Gi"}
					limits: {cpu: 4, memory: "4Gi"}
				}
			}

			initContainers: steamcmd: schema.#Hardened & {
				image: {
					repository: "ghcr.io/joker9944/steamcmd"
					tag:        "1.0.0@sha256:1b3218ba77ba165b17c0aa6ac5ead5213be894afb0289574edb0cf28654a82f1"
				}
				args: [
					"+@sSteamCmdForcePlatformType windows",
					"+login anonymous",
					"+app_update 2857200 validate",
					"+quit",
				]
				resources: {
					requests: {cpu: 1, memory: "2Gi"}
					limits: {cpu: 1, memory: "2Gi"}
				}
			}
		}

		service: (name): {
			controller: name
			type:       "LoadBalancer"
			annotations: "metallb.io/loadBalancerIPs": "192.168.0.131"
			ports: {
				game: {port: 7777, protocol: "UDP"}
				"query-tcp": port: 27015
				"query-udp": {port: 27015, protocol: "UDP"}
			}
		}

		persistence: {
			steam: {
				type:       "persistentVolumeClaim"
				accessMode: "ReadWriteOnce"
				size:       "20Gi"
				globalMounts: [{path: "/home/steam"}]
			}
			saved: {
				type:       "persistentVolumeClaim"
				accessMode: "ReadWriteOnce"
				retain:     true
				size:       savedSize
				dataSourceRef: {apiGroup: "volsync.backube", kind: "ReplicationDestination", "name": "\(name)-dest-saved"}
				advancedMounts: (name): (name): [
					{path: "/home/steam/.steam/steam/steamapps/common/Abiotic Factor Dedicated Server/AbioticFactor/Saved"},
				]
			}
			tmp: type: "emptyDir"
		}
	}
}
