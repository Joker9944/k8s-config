package traefik

// cSpell:ignore geoblock kubernetescrd lukaszraczylo traefikoidc

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "traefik-system"
	dependsOn: ["certs-config", "metallb-config", "redis-operator"]
	extraSecretFiles: ["infrastructure/controllers/traefik/secrets/traefik.secret.yaml"]

	// The ingress controller's own namespace serves nothing, so it installs no
	// middlewares; every other namespace gets its own set.
	middlewares: false

	repositories: [
		_traefikRepo,
		schema.#HelmRepo & {name: "ot-helm", url: "https://ot-container-kit.github.io/helm-charts", interval: "30m"},
	]
	releases: [_traefik, _oidcRedis]
}

_traefikRepo: schema.#HelmRepo & {
	name:     "traefik"
	url:      "https://traefik.github.io/charts"
	interval: "30m"
}

_traefik: schema.#Release & {
	name:      "traefik"
	namespace: bundle.namespace
	chart:     "traefik"
	// renovate: datasource=helm packageName=traefik registryUrl=https://traefik.github.io/charts
	version:    "41.5.0"
	sourceName: _traefikRepo.name
	crds:       true

	values: {
		// a DaemonSet so externalTrafficPolicy: Local routes node-locally
		deployment: kind: "DaemonSet"
		tolerations: [schema.#Reserved.any]

		ingressClass: enabled: false

		// Generated CRD names join namespace and name with an underscore, which
		// every `@kubernetescrd` reference in the fleet spells out. The chart only
		// ever emits this flag when true, so returning to the legacy `-` scheme
		// needs a raw additionalArguments entry, not `safeNaming: false`.
		providers: kubernetesCRD: safeNaming: true

		// Backends that derive variable names from header names (nextcloud and
		// collabora on PHP-FPM, pgadmin on WSGI) read `X_Auth_User` as
		// `X-Auth-User`, so a client can spoof what Traefik manages.
		ports: {
			web: http: aliasHeadersStrategy:       "delete"
			websecure: http: aliasHeadersStrategy: "delete"
			traefik: http: aliasHeadersStrategy:   "delete"
			metrics: http: aliasHeadersStrategy:   "delete"
		}

		// the two plugins #Middlewares references: geoblock backs the country
		// whitelist, oidc backs the forward-auth chain
		experimental: plugins: {
			geoblock: {
				moduleName: "github.com/PascalMinder/geoblock"
				// renovate: datasource=github-tags depName=geoblock-traefik-plugin packageName=PascalMinder/geoblock versioning=semver-coerced
				version: "v0.3.8"
			}
			oidc: {
				moduleName: "github.com/lukaszraczylo/traefikoidc"
				// renovate: datasource=github-tags depName=oidc-traefik-plugin packageName=lukaszraczylo/traefikoidc versioning=semver-coerced
				version: "v1.0.35"
			}
		}

		log: {level: "INFO", format: "json"}
		accessLog: {
			enabled: true
			format:  "json"
			fields: headers: defaultMode: "keep"
		}

		service: {
			annotations: "metallb.io/loadBalancerIPs": "192.168.0.128"
			spec: externalTrafficPolicy:               "Local"
		}
	}
}

// Session store for the oidc plugin.
_oidcRedis: schema.#Release & {
	name:      "traefik-oidc-redis"
	namespace: bundle.namespace
	chart:     "redis-replication"
	// renovate: datasource=helm packageName=redis-replication registryUrl=https://ot-container-kit.github.io/helm-charts
	version:    "0.17.0"
	sourceName: "ot-helm"

	values: redisReplication: redisSecret: {
		secretName: name
		secretKey:  "password"
	}
}
