package kanidmcluster

// cSpell:ignore kanidmcluster kaniop

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#ConfigBundle & {
	needs: ["kanidm", "certificate"]
	wait: true
	resources: [_cert, _kanidm]
}

let ns = "kanidm-system"
let cluster = "kanidm"
let uid = 568

// Spelled as a repository/tag pair so renovate's image manager bumps it in the
// same PR as the legacy release; replication needs both on one version.
_image: {
	repository: "kanidm/server"
	tag:        "1.12.0@sha256:71b6ff5a9c9c32b632894d8acef5a2afc77941b35a0aa95dcee959fe688d5ce9"
}

_cert: {
	apiVersion: "cert-manager.io/v1"
	kind:       "Certificate"
	metadata: {"name": "\(cluster)-tls", namespace: ns}
	spec: {
		dnsNames: [
			"\(cluster).\(ns).svc",
			"\(cluster).\(ns).svc.cluster.local",
			"*.\(cluster).\(ns).svc.cluster.local",
			_kanidm.spec.domain,
		]
		issuerRef: {
			group: "cert-manager.io"
			kind:  "ClusterIssuer"
			name:  "nyx-intermediate-ca"
		}
		secretName: "\(cluster)-tls"
	}
}

_kanidm: {
	apiVersion: "kaniop.rs/v1beta1"
	kind:       "Kanidm"
	metadata: {name: cluster, namespace: ns}
	spec: {
		domain: "idm.vonarx.online"
		image:  "\(_image.repository):\(_image.tag)"
		// kaniop builds against the 1.11 client SDK and rejects 1.12 servers
		// (pando85/kaniop#1141). This also disables kaniop's backup transport.
		disableUpgradeChecks: true
		tlsSecretName:        _cert.spec.secretName
		replicaGroups: [{
			name:        "default"
			replicas:    1
			role:        "write_replica"
			primaryNode: true
			resources: {
				requests: {cpu: "50m", memory: "1Gi"}
				limits: memory: "2Gi"
			}
		}]
		storage: volumeClaimTemplate: spec: {
			accessModes: ["ReadWriteOnce"]
			resources: requests: storage: "500Mi"
		}
		securityContext: {
			runAsUser:    uid
			runAsGroup:   uid
			fsGroup:      uid
			runAsNonRoot: true
			seccompProfile: type: "RuntimeDefault"
		}
	}
}
