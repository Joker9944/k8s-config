@extern(embed)

package loki

// cSpell:ignore tsdb

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "loki"
	dependsOn: ["garage"]
	middlewares: false
	extraSecretFiles: ["infrastructure/observability/loki/secrets/loki.secret.yaml"]
	repositories: [_grafana]
	before: [_dashboards.out]
	releases: [_loki]
}

// Plaintext dashboard, read from disk at evaluation time. @embed cannot escape
// the package directory, which is why this file lives here.
_logs: _ @embed(file="files/logs.json", type=text)

// Fleet-wide, so it belongs to the store the panels read rather than to any one
// app. Grafana's sidecar searches every namespace, so the label is what places
// it, not the namespace.
_dashboards: schema.#ConfigMapFiles & {
	name: "loki-dashboards"
	ns:   bundle.namespace
	labels: {
		grafana_dashboard:            "1"
		"app.kubernetes.io/name":     "loki"
		"app.kubernetes.io/instance": "loki"
	}
	files: "logs.json": _logs
}

// The OSS loki chart: grafana.github.io kept the loki name for the
// Enterprise-Logs-only lineage (7.x+), OSS moved here at 6.55.0.
_grafana: schema.#HelmRepo & {name: "grafana-community", url: "https://grafana-community.github.io/helm-charts"}

_loki: schema.#Release & {
	name:      "loki"
	namespace: bundle.namespace
	chart:     "loki"
	// renovate: datasource=helm packageName=loki registryUrl=https://grafana-community.github.io/helm-charts
	version:    "18.12.1"
	sourceName: _grafana.name

	// Loki expands these out of its environment at startup, so the credentials
	// stay in the Secret instead of landing in the config the chart generates —
	// which is a ConfigMap. Per component rather than global.extraEnvFrom, which
	// would hand them to the memcached pods as well.
	_s3Env: [{secretRef: name: "loki-s3"}]

	values: {
		global: extraArgs: ["-config.expand-env=true"]

		"loki": {
			// auth needs a reverse proxy supplying basic auth, which nothing in
			// front of loki does today
			auth_enabled: false

			schemaConfig: configs: [{
				from:         "2024-01-01"
				store:        "tsdb"
				object_store: "s3"
				schema:       "v13"
				index: {prefix: "loki_index_", period: "24h"}
			}]

			pattern_ingester: enabled: true

			limits_config: {
				allow_structured_metadata: true
				volume_enabled:            true
				retention_period:          "168h" // 7 * 24h
				// TODO false so alloy can scrape all the logs
				reject_old_samples: false
			}

			querier: max_concurrent: 2

			// the garage buckets, addressed in-cluster
			storage: {
				type: "s3"
				bucketNames: {chunks: "loki-chunk", ruler: "loki-ruler", admin: "loki-admin"}
				s3: {
					accessKeyId:      "${AWS_ACCESS_KEY_ID}"
					secretAccessKey:  "${AWS_SECRET_ACCESS_KEY}"
					endpoint:         "http://garage.garage.svc.cluster.local:3900"
					region:           "nyx"
					signatureVersion: "v4"
					s3ForcePathStyle: true
					insecure:         true
					http_config: {}
				}
			}
		}

		chunksCache: resources: {
			requests: {memory: "983Mi", cpu: "500m"}
			limits: memory: "9830Mi"
		}

		deploymentMode: "SimpleScalable"

		// Loki replicates above the volume — replication_factor 3 puts every line on
		// three ingesters, and everything durable is in Garage — so a replica
		// underneath would pay for the same bytes twice. max_chunk_age bounds the
		// ingester WAL at roughly two hours of ingest, which is why these sit far
		// below the chart's 10Gi default.
		// The gateway was the single largest log source in the cluster — a third of
		// everything nyx shipped, and all of it 2xx: kube-probes, the canary, and
		// alloy's own pushes. Loki logs its own requests in logfmt with the query,
		// byte counts and cache statistics attached, so the access log only
		// duplicated the successful half of that.
		gateway: {
			// "Enable logging of 2xx and 3xx HTTP requests", and on by default. Off,
			// the chart wraps access_log in `if=$loggable` so only the rest survives.
			verboseLogging: false

			nginxConfig: {
				// A JSON line carrying `level` is classified by loki's own distributor
				// (DefaultAllowedLevelFields), so this needs no alloy pipeline at all.
				//
				// The name has to stay `main`: the chart hardcodes `access_log … main`,
				// so renaming the format stops nginx at startup. escape=json is what
				// keeps a quote in a URI or user agent from breaking the object, and
				// $upstream_status is quoted because it is empty when no upstream was
				// reached — where $status and $request_time are always present.
				logFormat: #"""
					main escape=json '{"level":"$log_level","status":$status,"method":"$request_method",'
					  '"path":"$uri","query":"$args","duration":$request_time,'
					  '"upstream_status":"$upstream_status","remote_addr":"$remote_addr",'
					  '"user_agent":"$http_user_agent"}';
					"""#

				// Injected into the http block, which is where a map has to live. It is
				// read by a log_format parsed earlier in the file; nginx resolves
				// variable names after the whole config is loaded, so the forward
				// reference holds. 4xx/5xx split the way gotify splits its own.
				httpSnippet: #"""
					map $status $log_level {
					  ~^5  error;
					  ~^4  warn;
					  default info;
					}
					"""#
			}
		}

		backend: {
			replicas:     3
			extraEnvFrom: _s3Env
			persistence: {storageClass: "longhorn-local-strict", size: "2Gi"}
		}
		read: {replicas: 3, extraEnvFrom: _s3Env}
		write: {
			replicas:     3
			extraEnvFrom: _s3Env
			persistence: {storageClass: "longhorn-local-strict", size: "4Gi"}
		}
	}
}
