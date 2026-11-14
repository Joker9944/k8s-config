@extern(embed)

package kanidm

// cSpell:ignore BINDADDRESS kanidmd LDAPBINDADDRESS ldaps

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "kanidm"

	// No ingress: idm.vonarx.online is served by kanidm-cluster. LDAPS still
	// terminates here, on a certificate off the private CA.
	middlewares:   false
	namespaceCert: true

	before: [_logs.out, _replication.out, _partnerCert]
	releases: [_kanidm]
}

_serverToml: _ @embed(file="files/server.toml", type=text)

// Replication with the kaniop cluster in kanidm-system, which is the primary.
// kanidm takes a partner certificate only inline, so the file is a template the
// init container fills from _partnerCert.
_replication: schema.#ConfigMapFiles & {
	name: "kanidm-replication"
	ns:   bundle.namespace
	files: "server.toml": _serverToml
}

// Filled by reflector from the operator-owned kanidm-default-0-cert, whose
// reflection-allowed annotations are set by hand: kaniop has no field for them.
_partnerCert: {
	apiVersion: "v1"
	kind:       "Secret"
	metadata: {
		name:      "kanidm-replication-partner-cert"
		namespace: bundle.namespace
		annotations: "reflector.v1.k8s.emberstack.com/reflects": "kanidm-system/kanidm-default-0-cert"
	}
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
	let pathConfig = "/config/server.toml"
	let host = "idm.vonarx.online"

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

	// The private-CA certificate #Bundle emits, which the pod mounts for LDAPS.
	_cert: (schema.#NamespaceCert & {ns: namespace}).out

	values: {
		defaultPodOptions: labels: _logs.podLabels

		controllers: kanidm: {
			type: "statefulset"
			// The subPath mounts below never see a renewed Secret in place, and
			// kanidmd re-reads its TLS files only on a SIGHUP nothing sends;
			// reloader rolls the statefulset when the certificate renews.
			annotations: "secret.reloader.stakater.com/reload": "\(_cert.spec.secretName),\(_partnerCert.metadata.name)"
			pod: securityContext: {
				runAsUser:    uid
				runAsGroup:   gid
				runAsNonRoot: true
				fsGroup:      gid
				seccompProfile: type: "RuntimeDefault"
			}
			initContainers: replication: schema.#Hardened & {
				image: {
					repository: "busybox"
					tag:        "1.37@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec"
				}
				env: PARTNER_CERT: valueFrom: secretKeyRef: {name: _partnerCert.metadata.name, key: "tls.der.b64url"}
				command: ["/bin/sh", "-c"]
				args: ["sed \"s|@PARTNER_CERT@|$PARTNER_CERT|\" /template/server.toml > \(pathConfig)"]
			}
			containers: kanidm: schema.#Hardened & {
				image: {
					repository: "kanidm/server"
					tag:        "1.12.1@sha256:77198131f28116203e105d2e42214203757d113a694f35de545669e75db5c96f"
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
					KANIDM_CONFIG:              pathConfig
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
				ports: {
					https: {primary: true, port: 443, targetPort: 8443}
					repl: {port: 8444, targetPort: 8444, protocol: "TCP"}
				}
			}
			ldaps: {
				controller: "kanidm"
				ports: ldaps: {port: 636, targetPort: 3636, protocol: "TCP"}
			}
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
			"replication-template": {
				type:   "configMap"
				"name": _replication.name
				advancedMounts: kanidm: replication: [{path: "/template", readOnly: true}]
			}
			"replication-config": {
				type: "emptyDir"
				advancedMounts: kanidm: {
					replication: [{path: "/config"}]
					kanidm: [{path: "/config", readOnly: true}]
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
	}
}
