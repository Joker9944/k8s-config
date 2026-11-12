package qbittorrent

// cSpell:ignore devic

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "qbittorrent"
	extraSecretFiles: ["apps/media/qbittorrent/secrets/qbittorrent.secret.yaml"]
	// gluetun runs as root with NET_ADMIN to bring up the tunnel
	namespaceLabels: "pod-security.kubernetes.io/enforce": "privileged"
	// the only ingress here is served from the tailnet, so no Traefik middleware
	middlewares: false
	releases: [_qbittorrent]
}

_qbittorrent: schema.#AppRelease & {
	name:      "qbittorrent"
	namespace: "qbittorrent"

	let uid = 6002
	let gid = 6000
	let portHTTP = 8080
	let vpnInterface = "wg0"
	let vpnSecret = "qbittorrent-vpn-config"

	// the UI is reachable only from the tailnet
	host:    "downloader.\(schema.#TailnetDomain)"
	tailnet: true

	let configSize = "500Mi"
	let partOf = "servarr"

	let probe = {
		custom:  true
		enabled: true
		spec: exec: command: [
			"/bin/sh", "-c",
			"curl --fail \"http://localhost:$QBITTORRENT__PORT/api/v2/app/version\" || exit 1",
		]
	}

	let gluetunProbe = {
		custom:  true
		enabled: true
		spec: exec: command: ["/gluetun-entrypoint", "healthcheck"]
	}

	_backup: schema.#VolsyncRestic & {
		app:        name, vol:  "config", size: configSize
		"uid":      uid, "gid": gid
		secretFile: "apps/media/qbittorrent/secrets/restic.secret.yaml"
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

		controllers: qbittorrent: {
			type: "statefulset"
			pod: securityContext: {
				runAsUser:           uid
				runAsGroup:          gid
				runAsNonRoot:        true
				fsGroup:             gid
				fsGroupChangePolicy: "OnRootMismatch"
				supplementalGroups: [568]
				seccompProfile: type: "RuntimeDefault"
			}

			initContainers: {
				gluetun: schema.#HardenedWritableRoot & {
					// a native sidecar: qbittorrent starts only once the tunnel is up
					restartPolicy: "Always"
					image: {
						repository: "ghcr.io/qdm12/gluetun"
						tag:        "v3.41.3@sha256:fa19cc76b2af13d57a8d3dc3066f2ada061b1c761b8aecf989b3877c0486e027"
					}
					securityContext: {
						runAsUser:    0
						runAsNonRoot: false
						capabilities: add: ["NET_ADMIN", "NET_RAW", "CHOWN", "SETUID", "SETGID", "FOWNER", "DAC_OVERRIDE"]
					}
					env: {
						FIREWALL_INPUT_PORTS:      portHTTP
						VPN_INTERFACE:             vpnInterface
						FIREWALL_OUTBOUND_SUBNETS: "\(schema.#PodCIDR),\(schema.#ServiceCIDR)"
						BLOCK_MALICIOUS:           "off"
						// the pod resolves through kube-dns, outside the tunnel
						DNS_KEEP_NAMESERVER: "on"
					}
					envFrom: [{secretRef: name: vpnSecret}]
					probes: {
						liveness: gluetunProbe & {spec: failureThreshold: 6}
						readiness: gluetunProbe
						startup: gluetunProbe & {spec: {failureThreshold: 30, periodSeconds: 5}}
					}
					resources: limits: "devic.es/tun": 1
				}
			}

			containers: {
				qbittorrent: schema.#Hardened & {
					image: {
						repository: "ghcr.io/home-operations/qbittorrent"
						tag:        "5.3.0@sha256:5a858e61f94cf2712391db32ed03556576c700858f3e62c4c6fcde262443ebd8"
					}
					env: {
						UMASK:             "0002"
						QBITTORRENT__PORT: portHTTP
						// gluetun forwards a port the VPN provider assigns; it lands
						// in the same secret the tunnel is configured from
						QBITTORRENT__BT_PORT: valueFrom: secretKeyRef: {
							name: vpnSecret
							key:  "FIREWALL_VPN_INPUT_PORTS"
						}
						QBT_BitTorrent__Session__Interface:                 vpnInterface
						QBT_BitTorrent__Session__InterfaceName:             vpnInterface
						QBT_BitTorrent__Session__DefaultSavePath:           "/mnt/media-data/.staging/qbittorrent/complete"
						QBT_BitTorrent__Session__TempPathEnabled:           true
						QBT_BitTorrent__Session__TempPath:                  "/mnt/media-data/.staging/qbittorrent/incomplete"
						QBT_Preferences__WebUI__LocalHostAuth:              false
						QBT_Preferences__WebUI__ReverseProxySupportEnabled: true
						QBT_Preferences__WebUI__TrustedReverseProxiesList:  schema.#PodCIDR
					}
					probes: {
						liveness: probe & {spec: failureThreshold: 6}
						readiness: probe
						startup: probe & {spec: {failureThreshold: 30, periodSeconds: 5}}
					}
					resources: {
						requests: {cpu: "50m", memory: "1Gi"}
						limits: memory: "2Gi"
					}
				}
			}
		}

		service: qbittorrent: {
			controller: "qbittorrent"
			ports: http: port: portHTTP
		}

		ingress: qbittorrent: {
			hosts: [{"host": host, paths: [{path: "/", service: {identifier: "qbittorrent", port: "http"}}]}]
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
				advancedMounts: qbittorrent: qbittorrent: [{path: "/config"}]
			}
			media: schema.#MediaData & {
				advancedMounts: qbittorrent: qbittorrent: [{path: "/mnt/media-data"}]
			}
		}
	}
}
