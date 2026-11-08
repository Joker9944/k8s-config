package traefik

// cSpell:ignore geoblock kubernetescrd lukaszraczylo traefikoidc

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "traefik-system"
	wait:      true
	needs: ["ingress-certificate", "redis"]
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
	version:    "42.3.1"
	sourceName: _traefikRepo.name
	crds:       true

	values: {
		// a DaemonSet so externalTrafficPolicy: Local routes node-locally, on the
		// WireGuard spokes only — a packet reaching a node with no tunnel and no
		// pod is dropped rather than forwarded
		deployment: kind: "DaemonSet"

		nodeSelector: "\(schema.#IngressSpoke)": "true"

		ingressClass: enabled: false

		// Generated CRD names join namespace and name with an underscore, which
		// every `@kubernetescrd` reference in the fleet spells out. The chart only
		// ever emits this flag when true, so returning to the legacy `-` scheme
		// needs a raw additionalArguments entry, not `safeNaming: false`.
		providers: kubernetesCRD: safeNaming: true

		// Backends that derive variable names from header names (pgadmin on
		// WSGI) read `X_Auth_User` as `X-Auth-User`, so a client can spoof
		// what Traefik manages.
		ports: {
			// the edge's nginx answers :80 itself, so nothing reaches this one
			web: {
				http: aliasHeadersStrategy: "delete"
				expose: default:            false
			}
			websecure: {
				http: aliasHeadersStrategy: "delete"

				// the tunnel's own port, fixed because the edge's nginx upstream
				// and the spokes' firewall rule both name it
				exposedPort: 8443
				nodePort:    schema.#EdgeNodePort

				// Only the hub may speak PROXY protocol. Get this wrong and every
				// request carries the hub's address instead of the client's —
				// which geoblock reads as a local request and allows, so the
				// country whitelist fails open.
				proxyProtocol: trustedIPs: [schema.#WireGuardHubIP]
				forwardedHeaders: trustedIPs: [schema.#WireGuardHubIP]
			}
			traefik: http: aliasHeadersStrategy: "delete"
			metrics: http: aliasHeadersStrategy: "delete"
		}

		// The chart already serves /metrics on the metrics entrypoint; this adds
		// the ClusterIP Service a monitor can select. The ServiceMonitor itself
		// is NOT here — see /architecture/capability-graph.md: `monitoring` would
		// point traefik at kube-prometheus-stack, which reaches traefik through
		// `ingress`. It lives in the traefik-observability-config bundle instead.
		metrics: prometheus: service: enabled: true

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
				version: "v1.0.63"
			}
		}

		log: {level: "INFO", format: "json"}
		accessLog: {
			enabled: true
			format:  "json"
			fields: headers: defaultMode: "keep"
		}

		service: spec: {
			type:                  "NodePort"
			externalTrafficPolicy: "Local"
		}
	}
}

// Session store for the oidc plugin.
_oidcRedis: schema.#Release & {
	name:      "traefik-oidc-redis"
	namespace: bundle.namespace
	chart:     "redis-replication"
	// renovate: datasource=helm packageName=redis-replication registryUrl=https://ot-container-kit.github.io/helm-charts
	version:    "0.17.1"
	sourceName: "ot-helm"

	values: redisReplication: redisSecret: {
		secretName: name
		secretKey:  "password"
	}
}
