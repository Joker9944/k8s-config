@extern(embed)

package kanidm

// cSpell:ignore BINDADDRESS kanidmd LDAPBINDADDRESS ldaps serverstransport

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "kanidm"

	// kanidm terminates TLS itself, so Traefik talks to it over HTTPS with a
	// certificate off the private CA.
	namespaceCert: true

	namespaceLabels: "vonarx.online/distribute-nyx-ca-cert-bundle": "true"

	before: [_dashboards.out]
	releases: [_kanidm]
}

// Plaintext dashboard, read from disk at evaluation time. @embed cannot escape
// the package directory, which is why this file lives here.
_kanidmLogs: _ @embed(file="files/kanidm-logs.json", type=text)

_dashboards: schema.#ConfigMapFiles & {
	name: "kanidm-dashboards"
	ns:   bundle.namespace
	labels: {
		grafana_dashboard:            "1"
		"app.kubernetes.io/name":     "kanidm"
		"app.kubernetes.io/instance": "kanidm"
	}
	files: "kanidm-logs.json": _kanidmLogs
}

_kanidm: schema.#AppRelease & {
	name:      "kanidm"
	namespace: bundle.namespace

	let uid = 568
	let gid = 568
	let pathTLSCrt = "/data/tls.crt"
	let pathTLSKey = "/data/tls.key"
	let dataSize = "500Mi"
	host: "idm.vonarx.online"

	let probe = {
		custom:  true
		enabled: true
		spec: exec: command: ["/sbin/kanidmd", "scripting", "healthcheck"]
	}

	_backup: schema.#VolsyncRestic & {
		app:        name, vol:  "data", size: dataSize
		"uid":      uid, "gid": gid
		secretFile: "infrastructure/security/kanidm/secrets/restic.secret.yaml"
	}
	backups: [_backup]

	// The private-CA certificate #Bundle emits, which the pod mounts and Traefik
	// verifies against.
	_cert: (schema.#NamespaceCert & {ns: namespace}).out

	values: {
		controllers: kanidm: {
			type: "statefulset"
			pod: securityContext: {
				runAsUser:    uid
				runAsGroup:   gid
				runAsNonRoot: true
				fsGroup:      gid
				seccompProfile: type: "RuntimeDefault"
			}
			containers: kanidm: schema.#Hardened & {
				image: {
					repository: "kanidm/server"
					tag:        "1.11.1@sha256:7c3d7ed868e91f78c24a7fb9c548876563b375a4203021b730d58369b97ad154"
				}
				env: {
					KANIDM_BINDADDRESS:         "[::]:8443"
					KANIDM_LDAPBINDADDRESS:     "[::]:3636"
					KANIDM_TRUST_X_FORWARD_FOR: true
					KANIDM_DB_PATH:             "/data/kanidm.db"
					KANIDM_TLS_CHAIN:           pathTLSCrt
					KANIDM_TLS_KEY:             pathTLSKey
					KANIDM_LOG_LEVEL:           "info"
					KANIDM_DOMAIN:              host
					KANIDM_ORIGIN:              "https://\(host):443"
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

		service: {
			kanidm: {
				controller: "kanidm"
				primary:    true
				// Traefik has to speak HTTPS to this service and verify the private
				// CA, which is what the ServersTransport below configures.
				annotations: "traefik.ingress.kubernetes.io/service.serverstransport":
					"\(namespace)_\(name)-transport@kubernetescrd"
				ports: https: {primary: true, port: 443, targetPort: 8443}
			}
			ldaps: {
				controller: "kanidm"
				ports: ldaps: {port: 636, targetPort: 3636, protocol: "TCP"}
			}
		}

		ingress: kanidm: {
			hosts: [{
				"host": host
				paths: [{path: "/", service: {identifier: "kanidm", port: "https"}}]
			}]
			tls: [{hosts: [host], secretName: "wildcard-vonarx-online-cert"}]
		}

		persistence: {
			data: {
				type:       "persistentVolumeClaim"
				accessMode: "ReadWriteOnce"
				retain:     true
				size:       dataSize
				dataSourceRef: {
					apiGroup: "volsync.backube"
					kind:     "ReplicationDestination"
					"name":   "\(name)-dest-data"
				}
			}
			"data-overlay-tls": {
				type:   "secret"
				"name": _cert.spec.secretName
				globalMounts: [
					{path: pathTLSCrt, subPath: "tls.crt"},
					{path: pathTLSKey, subPath: "tls.key"},
				]
			}
		}

		rawResources: transport: {
			apiVersion: "traefik.io/v1alpha1"
			kind:       "ServersTransport"
			spec: spec: {
				serverName: "\(name).\(namespace)"
				rootCAs: [{secret: "nyx-ca-cert-bundle"}]
			}
		}
	}
}
