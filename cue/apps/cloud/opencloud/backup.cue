@extern(embed)

package opencloud

import "github.com/joker9944/k8s-config/schema"

// RESTORE: true while a restore is running (migration, bootstrap, DR) so the
// ReplicationDestination exists for the PVC to populate from; false in steady
// state, matching the fleet's disabled-destination philosophy.
_restore: true

let dataSize = "10Gi"

// The chart's securityContext runs opencloud as 1000/1000.
_backup: schema.#VolsyncRestic & {
	app:        "opencloud", vol: "data", size: dataSize
	uid:        1000, gid:        1000
	ns:         bundle.namespace
	secretFile: "apps/cloud/opencloud/secrets/restic.secret.yaml"
}

_backupObjects: [
	_dataPVC,
	_backup.out["source-data"].manifest,
	if _restore {_backup.out["dest-data"].manifest},
	_backupSA,
	_backupRole,
	_backupRoleBinding,
	_backupCronJob,
]

// The chart's own PVC has no dataSourceRef knob and the field is immutable
// after creation, so the claim is declared here and handed to the chart via
// existingClaim. The name follows #VolsyncRestic's `<app>-<vol>` convention.
// NOTE: the level-3 Kustomization prunes — if this ever leaves git, the PVC
// and the data on it are deleted.
_dataPVC: {
	apiVersion: "v1"
	kind:       "PersistentVolumeClaim"
	metadata: {name: "opencloud-data", namespace: bundle.namespace}
	spec: {
		accessModes: ["ReadWriteOnce"]
		storageClassName: "longhorn"
		resources: requests: storage: dataSize
		dataSourceRef: {apiGroup: "volsync.backube", kind: "ReplicationDestination", name: "opencloud-dest-data"}
	}
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
		{apiGroups: ["apps"], resources: ["deployments/scale"], verbs: ["get", "update", "patch"]},
		{apiGroups: ["volsync.backube"], resources: ["replicationsources"], verbs: ["get", "list", "watch", "patch"]},
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
			// on a hang. No activeDeadlineSeconds — it would kill the pod before
			// the trap that scales the deployment back up.
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
					name:    "backup"
					image:   "\(_backupImage.repository):\(_backupImage.tag)"
					command: ["python3", "-c", _backupScript]
					env: [
						// kubectl and rclone cache under $HOME; / is read-only
						{name: "HOME", value: "/tmp"},
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
