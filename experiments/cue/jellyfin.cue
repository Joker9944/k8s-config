package nyx

jellyfin: #Bundle & {
	namespace: "jellyfin"
	before: [{
		apiVersion: "v1"
		kind:       "Secret"
		type:       "Opaque"
		metadata: {name: "jellyfin-secret-values", namespace: "jellyfin"}
		data: "values.yaml": secretData
	}]
	releases: [_jellyfin]
}

_jellyfin: #Release & {
	name:      "jellyfin"
	namespace: "jellyfin"

	secretValuesName: "jellyfin-secret-values"

	let uid = 6003
	let gid = 6000
	let portHTTP = 8096
	host:  "jellyfin.vonarx.online"
	chain: "chain-country-whitelist"

	let configSize = "10Gi"

	let probe = {
		custom:  true
		enabled: true
		spec: httpGet: {path: "/health", port: portHTTP}
	}

	_backup: #VolsyncRestic & {
		app:   name, vol:  "config", size: configSize
		"uid": uid, "gid": gid
	}

	values: {
		controllers: jellyfin: {
			type: "statefulset"
			pod: {
				securityContext: {
					runAsUser:    uid
					runAsGroup:   gid
					runAsNonRoot: true
					fsGroup:      gid
					supplementalGroups: [44, 107, 568]
					seccompProfile: type: "RuntimeDefault"
				}
				tolerations: [{key: "nvidia.com/gpu", operator: "Exists", effect: "NoSchedule"}]
				affinity: nodeAffinity: preferredDuringSchedulingIgnoredDuringExecution: [{
					weight: 10
					preference: matchExpressions: [{key: "vonarx.online/nfs-host", operator: "Exists"}]
				}]
			}
			containers: jellyfin: #Hardened & {
				image: {
					repository: "ghcr.io/jellyfin/jellyfin"
					tag:        "10.11.11@sha256:45f648c382a0c8b552582fcea40e95cb17c5d475473a891cba0eb7523fb92112"
				}
				env: {
					UMASK:                       "0002"
					NVIDIA_DRIVER_CAPABILITIES:  "all"
					JELLYFIN_PublishedServerUrl: "https://jellyfin.vonarx.online"
				}
				probes: {
					liveness: probe & {spec: failureThreshold: 6}
					readiness: probe
					startup: probe & {spec: {failureThreshold: 30, periodSeconds: 5}}
				}
				resources: {
					requests: {cpu: "10m", memory: "1Gi"}
					limits: {memory: "8Gi", "nvidia.com/gpu": 1}
				}
			}
		}

		service: {
			jellyfin: {
				controller: "jellyfin"
				primary:    true
				ports: http: {primary: true, port: portHTTP}
			}
			autodiscovery: {
				controller: "jellyfin"
				type:       "LoadBalancer"
				annotations: "metallb.universe.tf/loadBalancerIPs": "192.168.0.130"
				ports: {
					"service-discovery": {port: 1900, protocol: "UDP"}
					"client-discovery": {port: 7359, protocol: "UDP"}
				}
			}
		}

		// annotations (incl. the namespace-qualified middleware) come from #App
		ingress: jellyfin: {
			hosts: [{host: "jellyfin.vonarx.online", paths: [{path: "/", service: {identifier: "jellyfin", port: "http"}}]}]
			tls: [{hosts: ["jellyfin.vonarx.online"], secretName: "wildcard-vonarx-online-cert"}]
		}

		persistence: {
			config: {
				type:       "persistentVolumeClaim"
				accessMode: "ReadWriteOnce"
				retain:     true
				size:       configSize
				dataSourceRef: {apiGroup: "volsync.backube", kind: "ReplicationDestination", "name": "\(name)-dest-config"}
				advancedMounts: jellyfin: jellyfin: [{path: "/config"}]
			}
			transcodes: {type: "emptyDir", advancedMounts: jellyfin: jellyfin: [{path: "/config/transcodes"}]}
			cache: {type: "emptyDir", advancedMounts: jellyfin: jellyfin: [{path: "/cache"}]}
			media: {
				type:   "nfs"
				server: "192.168.0.10"
				path:   "/mnt/chronos/media-data"
				advancedMounts: jellyfin: jellyfin: [{path: "/mnt/media-data"}]
			}
			tmp: type: "emptyDir"
		}

		rawResources: _backup.out
	}
}
