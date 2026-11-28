package genericdeviceplugin

// cSpell:ignore genericdeviceplugin squat

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace:   "generic-device-plugin"
	middlewares: false
	namespaceLabels: {
		"pod-security.kubernetes.io/enforce": "privileged"
		"pod-security.kubernetes.io/warn":    "privileged"
		"pod-security.kubernetes.io/audit":   "privileged"
	}
	releases: [_genericDevicePlugin]
}

_genericDevicePlugin: schema.#AppRelease & {
	name:      "generic-device-plugin"
	namespace: bundle.namespace

	values: {
		controllers: "generic-device-plugin": {
			type: "daemonset"
			pod: {
				securityContext: {
					runAsNonRoot: false
					seccompProfile: type: "RuntimeDefault"
				}
				tolerations: [
					{operator: "Exists", effect: "NoExecute"},
					{operator: "Exists", effect: "NoSchedule"},
				]
				priorityClassName: "system-node-critical"
			}
			containers: "generic-device-plugin": schema.#HardenedPrivileged & {
				image: {
					repository: "squat/generic-device-plugin"
					tag:        "latest@sha256:6fd8023741b24c0302a97153605ff77f4d55535a4b5a8b0c8502b208e8310525"
				}
				resources: {
					requests: {cpu: "50m", memory: "10Mi"}
					limits: {cpu: "50m", memory: "20Mi"}
				}
				// advertises /dev/net/tun to the qbittorrent pod
				args: ["--device", """
					name: tun
					groups:
					  - count: 1000
					    paths:
					      - path: /dev/net/tun

					"""]
			}
		}

		persistence: {
			"device-plugin": {
				type:     "hostPath"
				hostPath: "/var/lib/kubelet/device-plugins"
				globalMounts: [{path: "/var/lib/kubelet/device-plugins"}]
			}
			dev: {
				type:     "hostPath"
				hostPath: "/dev"
				globalMounts: [{path: "/dev"}]
			}
		}
	}
}
