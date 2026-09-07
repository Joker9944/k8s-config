package loki

// cSpell:ignore tsdb

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "loki"
	source:    "infrastructure/base/loki"
	dependsOn: ["garage"]
	middlewares: false
	extraSecretFiles: ["infrastructure/observability/loki/secrets/loki.secret.yaml"]
	repositories: [_grafana]
	releases: [_loki]
}

_grafana: schema.#HelmRepo & {name: "grafana", url: "https://grafana.github.io/helm-charts"}

_loki: schema.#Release & {
	name:       "loki"
	namespace:  bundle.namespace
	chart:      "loki"
	version:    "6.55.0"
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
		backend: {replicas: 3, extraEnvFrom: _s3Env}
		read: {replicas: 3, extraEnvFrom: _s3Env}
		write: {replicas: 3, extraEnvFrom: _s3Env}
	}
}
