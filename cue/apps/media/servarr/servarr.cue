@extern(embed)

package servarr

import (
	"list"
	"github.com/joker9944/k8s-config/schema"
)

// cSpell:ignore INSTANCENAME APIKEY MAINDB LOGDB

// Six releases in one namespace sharing one Postgres cluster. The four *arr
// apps differ by roughly eight parameters; everything else is #Arr.

_servarrLabel: "app.kubernetes.io/part-of": "servarr"

_servarrPod: {
	global: labels:            _servarrLabel
	defaultPodOptions: labels: _servarrLabel
	defaultPodOptions: topologySpreadConstraints: [{
		maxSkew:           1
		topologyKey:       "kubernetes.io/hostname"
		whenUnsatisfiable: "ScheduleAnyway"
		labelSelector: matchLabels: _servarrLabel
	}]
}

_cnpgSecretRef: {
	name:  string
	_user: name
	user: valueFrom: secretKeyRef: {"name": "\(_user)-cnpg-user", key: "username"}
	pass: valueFrom: secretKeyRef: {"name": "\(_user)-cnpg-user", key: "password"}
}

#Arr: {
	name:         string
	app:          string // controller / container / service key
	envPrefix:    string
	instanceName: string
	image: {repository: string, tag: schema.#Digest}
	uid:  int
	gid:  int | *6000
	port: int
	cpu:  string
	mem: {request: string, limit: string}

	// prowlarr diverges: no media mounts, no umask, a bare 568 group, and an
	// unquoted COMPlus value. Modelled rather than hidden.
	media:        bool | *true
	umask:        bool | *true
	rootMounts:   bool | *true
	diagnostics:  string | int | *"0"
	databaseRole: string | *""

	_secrets: _cnpgSecretRef & {"name": name}
	_probe: {
		enabled: true
		custom:  true
		spec: httpGet: {"port": port, path: "/ping"}
	}

	release: schema.#AppRelease & {
		"name":     name
		namespace:  "servarr"
		host:       "\(name).vonarx.online"
		ingressKey: app
		extraMiddlewares: ["\(name)-oidc"]

		values: _servarrPod & {
			defaultPodOptions: labels: _logs.podLabels

			controllers: (app): {
				pod: securityContext: {
					runAsUser:    uid
					runAsGroup:   gid
					runAsNonRoot: true
					fsGroup:      gid
					if rootMounts {
						fsGroupChangePolicy: "OnRootMismatch"
						supplementalGroups: [568]
					}
					seccompProfile: type: "RuntimeDefault"
				}

				containers: (app): schema.#Hardened & {
					"image": image
					env: {
						COMPlus_EnableDiagnostics: diagnostics
						if umask {UMASK: "0002"}
						"\(envPrefix)__APP__INSTANCENAME": instanceName
						"\(envPrefix)__AUTH__APIKEY": valueFrom: secretKeyRef: {
							"name": "\(name)-api-key", key: "key"
						}
						"\(envPrefix)__AUTH__METHOD":       "External"
						"\(envPrefix)__AUTH__REQUIRED":     "Enabled"
						"\(envPrefix)__SERVER__PORT":       port
						"\(envPrefix)__LOG__LEVEL":         "info"
						"\(envPrefix)__POSTGRES__HOST":     "servarr-cnpg-rw"
						"\(envPrefix)__POSTGRES__USER":     _secrets.user
						"\(envPrefix)__POSTGRES__PASSWORD": _secrets.pass
						"\(envPrefix)__POSTGRES__MAINDB":   "\(name)-main"
						"\(envPrefix)__POSTGRES__LOGDB":    "\(name)-log"
					}
					probes: {
						liveness: _probe & {spec: failureThreshold: 6}
						readiness: _probe
						startup: _probe & {spec: {failureThreshold: 30, periodSeconds: 5}}
					}
					resources: {
						requests: {"cpu": cpu, memory: mem.request}
						limits: memory: mem.limit
					}
				}

				initContainers: postgresql: schema.#Hardened & {
					image: {
						repository: "ghcr.io/joker9944/postgresql-client"
						tag:        "4.0.0@sha256:e8143037a7aff99758c35b2f35a76bf290ccd6cbaded614de793e8a1a2496f8d"
					}
					env: {
						PGHOST:        "servarr-cnpg-r"
						PGUSER:        _secrets.user
						PGPASSWORD:    _secrets.pass
						MAIN_DATABASE: "\(name)-main"
						LOG_DATABASE:  "\(name)-log"
						if databaseRole != "" {DATABASE_ROLE: databaseRole}
					}
					command: ["/bin/sh", "-c"]
					args: ["""
						echo "Testing connection for DB $MAIN_DATABASE and $LOG_DATABASE on $PGHOST"
						until
						  pg_isready --dbname="$MAIN_DATABASE"
						  pg_isready --dbname="$LOG_DATABASE"
						  do sleep 5
						done
						echo "DB $MAIN_DATABASE and $LOG_DATABASE available on $PGHOST"

						"""]
				}
			}

			service: (app): {
				controller: app
				ports: http: "port": port
			}

			ingress: (app): {
				hosts: [{host: "\(name).vonarx.online", paths: [{
					path: "/", service: {identifier: app, port: "http"}
				}]}]
				tls: [{hosts: ["\(name).vonarx.online"], secretName: "wildcard-vonarx-online-cert"}]
			}

			persistence: {
				config: type: "emptyDir"
				tmp: type:    "emptyDir"
				if media {
					"media-cover-overlay": {
						type:       "persistentVolumeClaim"
						retain:     false
						accessMode: "ReadWriteOnce"
						size:       "1Gi"
						globalMounts: [{path: "/config/MediaCover"}]
					}
					"media": schema.#MediaData & {
						globalMounts: [{path: "/mnt/media-data"}]
					}
				}
			}

			rawResources: {
				for k in ["main", "log"] {
					(k): {
						apiVersion: "postgresql.cnpg.io/v1"
						kind:       "Database"
						spec: spec: {
							"name": "\(name)-\(k)"
							owner:  name
							cluster: "name": "servarr-cnpg"
							databaseReclaimPolicy: "retain"
						}
					}
				}
				oidc: {
					apiVersion: "traefik.io/v1alpha1"
					kind:       "Middleware"
					spec: spec: plugin: oidc: {
						providerURL:          "https://idm.vonarx.online/oauth2/openid/\(name)"
						clientID:             name
						clientSecret:         "urn:k8s:secret:\(name)-oidc:CLIENT_SECRET"
						sessionEncryptionKey: "urn:k8s:secret:\(name)-oidc:SESSION_ENCRYPTION_KEY"
						callbackURL:          "/oauth2/callback"
						enablePKCE:           true
						scopes: ["groups"]
						allowedRolesAndGroups: ["servarr_admins@idm.vonarx.online"]
						allowedUserDomains: ["vonarx.online"]
						excludedURLs: ["/favicon.ico"]
						redis: {
							enabled:  true
							address:  "traefik-oidc-redis-master.traefik-system.svc.cluster.local:6379"
							password: "urn:k8s:secret:traefik-oidc-redis:password"
						}
						logLevel: "info"
					}
				}
			}
		}
	}
}

_arrs: [
	#Arr & {
		name:         "prowlarr", app: "prowlarr", envPrefix: "PROWLARR"
		instanceName: "Prowlarr"
		image: {
			repository: "ghcr.io/home-operations/prowlarr"
			tag:        "2.6.3.5592@sha256:8c9ee448bb6de0e3e8b9c2f536b7a3455ec6ff5e184c2fb2a8602791b2757442"
		}
		uid: 568, gid: 568, port: 9696
		cpu: "30m", mem: {request: "400Mi", limit: "700Mi"}
		media: false, umask: false, rootMounts: false, diagnostics: 0
	},
	#Arr & {
		name:         "radarr-standard", app: "radarr", envPrefix: "RADARR"
		instanceName: "Radarr Standard"
		image: {
			repository: "ghcr.io/home-operations/radarr"
			tag:        "6.4.3.10645@sha256:0ebb4ae26ee9522674a4ad1855e926fd6b97c534ff982644c9c9a87bca740077"
		}
		uid: 6005, port: 7878
		cpu: "20m", mem: {request: "500Mi", limit: "700Mi"}
	},
	#Arr & {
		name:         "sonarr-anime", app: "sonarr", envPrefix: "SONARR"
		instanceName: "Sonarr Anime"
		image: {
			repository: "ghcr.io/home-operations/sonarr"
			tag:        "4.0.19.3011@sha256:47d56de90c81eb2a8f0d36771328a95e7299609579b88db82b1473c314f26a47"
		}
		uid: 6006, port: 8989
		cpu: "40m", mem: {request: "500Mi", limit: "700Mi"}
	},
	#Arr & {
		name:         "sonarr-standard", app: "sonarr", envPrefix: "SONARR"
		instanceName: "Sonarr Standard"
		image: {
			repository: "ghcr.io/home-operations/sonarr"
			tag:        "4.0.19.3011@sha256:47d56de90c81eb2a8f0d36771328a95e7299609579b88db82b1473c314f26a47"
		}
		uid: 6006, port: 8989
		cpu: "40m", mem: {request: "500Mi", limit: "700Mi"}
		databaseRole: "sonarr-standard-main-group"
	},
]

// Plaintext config, read from disk at evaluation time. @embed cannot escape
// the package directory, which is why these files live here.
_recyclarrConfig:   _ @embed(file="files/recyclarr.yml", type=text)
_recyclarrSettings: _ @embed(file="files/settings.yml", type=text)
_servarrLogs:       _ @embed(file="files/servarr.alloy", type=text)

// The *arr log pipeline, shipped with the apps rather than with alloy. Claims
// only the four #Arr pods: flaresolverr and recyclarr share _servarrPod but log
// nothing like an *arr, so the label goes on #Arr and not on the shared block.
_logs: schema.#AlloyPipeline & {
	app:    "servarr"
	ns:     bundle.namespace
	config: _servarrLogs
}

_flaresolverr: schema.#AppRelease & {
	name:      "flaresolverr"
	namespace: "servarr"
	values: _servarrPod & {
		controllers: flaresolverr: {
			pod: securityContext: {
				runAsNonRoot: false
				seccompProfile: type: "RuntimeDefault"
			}
			// flaresolverr runs a headless browser and cannot take a read-only root
			containers: flaresolverr: schema.#HardenedWritableRoot & {
				image: {
					repository: "ghcr.io/flaresolverr/flaresolverr"
					tag:        "v3.5.0@sha256:139dfee1c6f89249c8d665d1333a42e8ec74ec0a86bc6bb1c8461e10d3a66a47"
				}
				env: {LOG_LEVEL: "info", PORT: 8191}
				let p = {
					enabled: true
					custom:  true
					spec: httpGet: {path: "/health", port: 8191}
				}
				probes: {
					liveness: p & {spec: failureThreshold: 6}
					readiness: p
					startup: p & {spec: {failureThreshold: 30, periodSeconds: 5}}
				}
				resources: {
					requests: {cpu: "10m", memory: "250Mi"}
					limits: memory: "1Gi"
				}
			}
		}
		service: flaresolverr: {
			controller: "flaresolverr"
			ports: http: port: 8191
		}
	}
}

_recyclarr: schema.#AppRelease & {
	name:      "recyclarr"
	namespace: "servarr"
	values: _servarrPod & {
		controllers: recyclarr: {
			type: "cronjob"
			cronjob: {
				schedule:                "@daily"
				concurrencyPolicy:       "Forbid"
				backoffLimit:            6
				successfulJobsHistory:   3
				failedJobsHistory:       3
				startingDeadlineSeconds: 120
				ttlSecondsAfterFinished: 120
			}
			pod: securityContext: {
				runAsUser:           568
				runAsGroup:          568
				runAsNonRoot:        true
				fsGroup:             568
				fsGroupChangePolicy: "OnRootMismatch"
				seccompProfile: type: "RuntimeDefault"
			}
			containers: recyclarr: schema.#Hardened & {
				image: {
					repository: "ghcr.io/recyclarr/recyclarr"
					tag:        "7.5.2@sha256:2550848d43a453f2c6adf3582f2198ac719f76670691d76de0819053103ef2fb"
				}
				command: ["recyclarr", "sync"]
			}
		}
		persistence: {
			config: {
				type:         "persistentVolumeClaim"
				accessMode:   "ReadWriteOnce"
				size:         "500Mi"
				storageClass: "longhorn"
			}
			"config-overlay": {
				type: "configMap"
				name: "recyclarr-config-overlay"
				globalMounts: [
					{path: "/config/recyclarr.yml", subPath: "recyclarr.yml"},
					{path: "/config/settings.yml", subPath: "settings.yml"},
				]
			}
			"secret-overlay": {
				type: "secret"
				name: "recyclarr-secret-overlay"
				globalMounts: [{path: "/config/secrets.yml", subPath: "secrets.yml"}]
			}
			tmp: type: "emptyDir"
		}
	}
}

// A recovery bootstrap requires its own archive destination to be empty, so the
// two names can never be the same. Every restore moves _archiveTo's old value
// into _recoverFrom and picks an unused name for _archiveTo; the counter is a
// token, not arithmetic. Reversing these two is what makes a restore fail with
// "Expected empty archive".
_archiveTo:   "servarr-cnpg-6"
_recoverFrom: "servarr-cnpg"

_cnpgCluster: {
	apiVersion: "postgresql.cnpg.io/v1"
	kind:       "Cluster"
	metadata: {name: "servarr-cnpg", namespace: "servarr"}
	spec: {
		description: "PostgreSQL Cluster for the Servarr family of apps"
		instances:   3
		imageCatalogRef: {
			apiGroup: "postgresql.cnpg.io"
			kind:     "ClusterImageCatalog"
			name:     "postgresql-standard-trixie"
			major:    16
		}
		plugins: [{
			name:          "barman-cloud.cloudnative-pg.io"
			isWALArchiver: true
			parameters: {barmanObjectName: "storj", serverName: _archiveTo}
		}]
		storage: {size: "3Gi", storageClass: "longhorn-local-strict"}
		walStorage: {size: "3Gi", storageClass: "longhorn-local-strict"}
		affinity: {enablePodAntiAffinity: true, podAntiAffinityType: "required"}
		bootstrap: recovery: source: "clusterBackup"
		externalClusters: [{
			name: "clusterBackup"
			plugin: {
				name: "barman-cloud.cloudnative-pg.io"
				parameters: {barmanObjectName: "storj", serverName: _recoverFrom}
			}
		}]
		// Roles are derived from _arrs: adding an app cannot forget its role.
		managed: roles: list.Concat([
			[{name: "servarr", login: true, superuser: true, passwordSecret: name: "servarr-cnpg-user"}],
			[for a in _arrs {{name: a.name, login: true, passwordSecret: "name": "\(a.name)-cnpg-user"}}],
		])
	}
}

_objectStore: {
	apiVersion: "barmancloud.cnpg.io/v1"
	kind:       "ObjectStore"
	metadata: {name: "storj", namespace: "servarr"}
	spec: {
		retentionPolicy: "30d"
		configuration: {
			destinationPath: "s3://k8s-cnpg-backup"
			endpointURL:     "https://gateway.storjshare.io"
			s3Credentials: {
				accessKeyId: {name: "backup-s3-credentials", key: "accessKey"}
				secretAccessKey: {name: "backup-s3-credentials", key: "secretKey"}
			}
			wal: compression: "gzip"
		}
		instanceSidecarConfiguration: env: [
			{name: "AWS_REQUEST_CHECKSUM_CALCULATION", value: "when_required"},
			{name: "AWS_RESPONSE_CHECKSUM_VALIDATION", value: "when_required"},
		]
	}
}

_scheduledBackup: {
	apiVersion: "postgresql.cnpg.io/v1"
	kind:       "ScheduledBackup"
	metadata: {name: "servarr-cnpg-daily", namespace: "servarr"}
	spec: {
		immediate: true
		schedule:  "@daily"
		cluster: name: "servarr-cnpg"
		backupOwnerReference: "self"
		method:               "plugin"
		pluginConfiguration: name: "barman-cloud.cloudnative-pg.io"
	}
}

bundle: schema.#Bundle & {
	namespace: "servarr"
	extraSecretFiles: [
		"apps/media/servarr/secrets/cnpg.secret.yaml",
		"apps/media/servarr/secrets/prowlarr.secret.yaml",
		"apps/media/servarr/secrets/radarr-standard.secret.yaml",
		"apps/media/servarr/secrets/sonarr-anime.secret.yaml",
		"apps/media/servarr/secrets/sonarr-standard.secret.yaml",
		"apps/media/servarr/secrets/recyclarr.secret.yaml",
	]
	before: [
		{
			apiVersion: "v1"
			kind:       "ConfigMap"
			metadata: {name: "recyclarr-config-overlay", namespace: "servarr"}
			data: {
				"recyclarr.yml": _recyclarrConfig
				"settings.yml":  _recyclarrSettings
			}
		},
		_objectStore,
		_logs.out,
	]
	releases: list.Concat([
		[_flaresolverr],
		[for a in _arrs {a.release}],
		[_recyclarr],
	])
	after: [_cnpgCluster, _scheduledBackup]
}
