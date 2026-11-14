package kanidmcluster

// cSpell:ignore kanidmcluster kaniop

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#ConfigBundle & {
	needs: ["kanidm", "certificate", "ingress", "volsync"]
	wait: true
	secretFiles: [
		"infrastructure/security/kanidm-cluster/secrets/replication.secret.yaml",
		_backup.secretFile,
	]
	resources: [_cert, _transport, _kanidm, _backupSource]
}

let ns = "kanidm-system"
let cluster = "kanidm"
let uid = 568

// Spelled as a repository/tag pair so renovate's image manager bumps it in the
// same PR as the legacy release; replication needs both on one version.
_image: {
	repository: "kanidm/server"
	tag:        "1.12.1@sha256:77198131f28116203e105d2e42214203757d113a694f35de545669e75db5c96f"
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

// kanidm terminates TLS itself, so Traefik verifies it against the private CA.
_transport: {
	apiVersion: "traefik.io/v1alpha1"
	kind:       "ServersTransport"
	metadata: {name: "\(cluster)-transport", namespace: ns}
	spec: {
		serverName: "\(cluster).\(ns).svc"
		rootCAs: [{secret: "nyx-ca-cert-bundle"}]
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
		ldapPortName:         "ldaps"
		replicaGroups: [{
			name:     "default"
			replicas: 1
			role:     "write_replica"
			// The app-template instance in `kanidm` is the secondary and refreshes
			// from here; only one side may be primary.
			primaryNode: true
			resources: {
				requests: {cpu: "50m", memory: "1Gi"}
				limits: memory: "2Gi"
			}
		}]
		// The app-template instance, kept in step until it is decommissioned. Its
		// certificate is pinned in the secret and changes only on a manual renew.
		externalReplicationNodes: [{
			name:             "legacy"
			hostname:         "kanidm.kanidm.svc.cluster.local"
			port:             8444
			type:             "mutual-pull"
			automaticRefresh: false
			certificate: {name: "kanidm-legacy-replication-cert", key: "certificate"}
		}]
		service: annotations: "traefik.ingress.kubernetes.io/service.serverstransport":
			"\(ns)_\(_transport.metadata.name)@kubernetescrd"
		ingress: {
			annotations: (schema.#IngressAnnotations & {"ns": ns}).out
			tlsSecretName: "wildcard-vonarx-online-cert"
		}
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

// The primary's volume only: the other replicas refresh from it. Restore is not
// wired: the claim template cannot gain a dataSourceRef without recreating the
// StatefulSet. Revisit kaniop's own backup (KanidmBackupSchedule) once it
// leaves v1alpha1 and its restore reads kanidm 1.12 dumps.
_backup: schema.#VolsyncRestic & {
	app:        cluster, vol: "data", size: "500Mi"
	"uid":      uid, "gid":   uid
	pvc:        "\(cluster)-data-\(cluster)-default-0"
	secretFile: "infrastructure/security/kanidm-cluster/secrets/restic.secret.yaml"
}

_backupSource: _backup.out["source-data"].manifest & {
	metadata: {name: "\(cluster)-source-data", namespace: ns}
}
