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

	before: [_logs.out]
	releases: [_kanidm]
}

_kanidmLogs: _ @embed(file="files/kanidm.alloy", type=text)

// kanidm's log pipeline, shipped with the app rather than with alloy.
_logs: schema.#AlloyPipeline & {
	app:    "kanidm"
	ns:     bundle.namespace
	config: _kanidmLogs
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
		defaultPodOptions: labels: _logs.podLabels

		controllers: kanidm: {
			type: "statefulset"
			// The subPath mounts below never see a renewed Secret in place, and
			// kanidmd re-reads its TLS files only on a SIGHUP nothing sends;
			// reloader rolls the statefulset when the certificate renews.
			annotations: "secret.reloader.stakater.com/reload": _cert.spec.secretName
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
					tag:        "1.11.2@sha256:e45f00bd354c1fc1c06a4be484b4e87b094c431e78280f1d19e911815e63efb5"
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

		rawResources: transport: manifest: {
			apiVersion: "traefik.io/v1alpha1"
			kind:       "ServersTransport"
			spec: {
				serverName: "\(name).\(namespace)"
				rootCAs: [{secret: "nyx-ca-cert-bundle"}]
			}
		}
	}
}
