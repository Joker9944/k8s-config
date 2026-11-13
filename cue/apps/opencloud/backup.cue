@extern(embed)

package opencloud

import (
	"encoding/json"

	"github.com/joker9944/k8s-config/schema"
)

// RESTORE: true while a restore is running (bootstrap, DR) so the
// ReplicationDestination exists for the PVC to populate from; false in steady
// state, matching the fleet's disabled-destination philosophy.
_restore: false

// The chart's own data claim; it predates the backup and ships without a
// dataSourceRef, so a restore recreates it with one.
_dataClaim: "opencloud-opencloud-data"

// The chart's securityContext runs opencloud as 1000/1000.
_backup: schema.#VolsyncRestic & {
	app:        "opencloud", vol: "data"
	size:       _opencloud.values.opencloud.persistence.data.size
	uid:        1000, gid: 1000
	secretFile: "apps/opencloud/secrets/restic.secret.yaml"
	pvc:        _dataClaim
}

_backupObjects: [
	if _restore {_backupDest},
	_backupSA,
	_backupRole,
	_backupRoleBinding,
	_backupCronJob,
]

// Applied by backup.py, not Flux: the script sets spec.trigger.manual, which
// Flux would reset on every reconcile, and creating it inside the quiesce
// window keeps even its first sync consistent.
let _source = _backup.out["source-data"].manifest
_backupSource: {
	apiVersion: _source.apiVersion
	kind:       _source.kind
	metadata: {name: "opencloud-source-data", namespace: bundle.namespace}
	spec: {for k, v in _source.spec if k != "trigger" {(k): v}}
}

_backupDest: _backup.out["dest-data"].manifest & {
	metadata: {name: "opencloud-dest-data", namespace: bundle.namespace}
}

_backupSA: {
	apiVersion: "v1"
	kind:       "ServiceAccount"
	metadata: {name: "opencloud-backup", namespace: bundle.namespace}
}

_backupRole: {
	apiVersion: "rbac.authorization.k8s.io/v1"
	kind:       "Role"
	metadata: {name: "opencloud-backup", namespace: bundle.namespace}
	rules: [
		{apiGroups: ["apps"], resources: ["deployments"], verbs: ["get"]},
		{apiGroups: [""], resources: ["pods"], verbs: ["list"]},
		{apiGroups: [""], resources: ["persistentvolumeclaims"], verbs: ["get", "list", "watch", "patch"]},
		{apiGroups: ["apps"], resources: ["deployments/scale"], verbs: ["get", "update", "patch"]},
		{apiGroups: ["volsync.backube"], resources: ["replicationsources"], verbs: ["get", "list", "watch", "create", "patch"]},
		{apiGroups: ["helm.toolkit.fluxcd.io"], resources: ["helmreleases"], verbs: ["get", "patch"]},
	]
}

_backupRoleBinding: {
	apiVersion: "rbac.authorization.k8s.io/v1"
	kind:       "RoleBinding"
	metadata: {name: "opencloud-backup", namespace: bundle.namespace}
	roleRef: {apiGroup: "rbac.authorization.k8s.io", kind: "Role", name: "opencloud-backup"}
	subjects: [{kind: "ServiceAccount", name: "opencloud-backup", namespace: bundle.namespace}]
}

_backupScript: _ @embed(file="files/backup.py", type=text)

_backupImage: {
	repository: "ghcr.io/joker9944/backup-runner"
	// TODO replace with the digest of the first published image
	tag: "1.0.0@sha256:0000000000000000000000000000000000000000000000000000000000000000"
}

_backupCronJob: {
	apiVersion: "batch/v1"
	kind:       "CronJob"
	metadata: {name: "opencloud-backup", namespace: bundle.namespace}
	spec: {
		schedule:          "0 3 * * *"
		timeZone:          "Europe/Zurich"
		concurrencyPolicy: "Forbid"
		jobTemplate: spec: {
			// One attempt; KubeJobFailed alerts on failure, KubeJobNotCompleted
			// on a hang.
			backoffLimit: 0
			template: spec: {
				serviceAccountName: "opencloud-backup"
				restartPolicy:      "Never"
				securityContext: {
					runAsUser:    65534
					runAsGroup:   65534
					runAsNonRoot: true
					seccompProfile: type: "RuntimeDefault"
				}
				containers: [{
					name:  "backup"
					image: "\(_backupImage.repository):\(_backupImage.tag)"
					command: ["python3", "-c", _backupScript]
					env: [
						// kubectl and rclone cache under $HOME; / is read-only
						{name: "HOME", value: "/tmp"},
						{name: "SOURCE_MANIFEST", value: json.Marshal(_backupSource)},
						{name: "RCLONE_CONFIG_SRC_TYPE", value: "s3"},
						{name: "RCLONE_CONFIG_SRC_PROVIDER", value: "Other"},
						{name: "RCLONE_CONFIG_SRC_ENDPOINT", value: "http://garage.garage.svc.cluster.local:3900"},
						{name: "RCLONE_CONFIG_SRC_REGION", value: "nyx"},
						{name: "RCLONE_CONFIG_SRC_ACCESS_KEY_ID", valueFrom: secretKeyRef: {name: "opencloud-s3", key: "accessKey"}},
						{name: "RCLONE_CONFIG_SRC_SECRET_ACCESS_KEY", valueFrom: secretKeyRef: {name: "opencloud-s3", key: "secretKey"}},
						{name: "RCLONE_CONFIG_DST_TYPE", value: "s3"},
						{name: "RCLONE_CONFIG_DST_PROVIDER", value: "Storj"},
						{name: "RCLONE_CONFIG_DST_ENDPOINT", value: "https://gateway.storjshare.io"},
					]
					// DST creds and DST_PATH (bucket/prefix), see secrets/rclone.secret.yaml
					envFrom: [{secretRef: name: "opencloud-rclone"}]
					securityContext: {
						allowPrivilegeEscalation: false
						readOnlyRootFilesystem:   true
						capabilities: drop: ["ALL"]
					}
					resources: {
						requests: {cpu: "50m", memory: "128Mi"}
						limits: memory: "1Gi"
					}
					volumeMounts: [{name: "tmp", mountPath: "/tmp"}]
				}]
				volumes: [{name: "tmp", emptyDir: {}}]
			}
		}
	}
}
