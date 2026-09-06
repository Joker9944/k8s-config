package traefik

// cSpell:ignore geoblock kubernetescrd lineofflight lukaszraczylo traefikoidc

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "traefik-system"
	source:    "infrastructure/base/traefik"
	dependsOn: ["certs-config", "metallb-config", "redis-operator"]
	secretFiles: ["infrastructure/controllers/traefik/secrets/traefik.secret.yaml"]

	// The ingress controller's own namespace serves nothing, so it installs no
	// middlewares; every other namespace gets its own set.
	middlewares: false

	repositories: [
		_traefikRepo,
		schema.#HelmRepo & {name: "bjw-s", url: "https://bjw-s-labs.github.io/helm-charts"},
		schema.#HelmRepo & {name: "ot-helm", url: "https://ot-container-kit.github.io/helm-charts", interval: "30m"},
	]
	releases: [_traefik, _geoLookup, _oidcRedis]
}

_traefikRepo: schema.#HelmRepo & {
	name:     "traefik"
	url:      "https://traefik.github.io/charts"
	interval: "30m"
}

_traefik: schema.#Release & {
	name:       "traefik"
	namespace:  bundle.namespace
	chart:      "traefik"
	version:    "39.0.9"
	sourceName: _traefikRepo.name
	crds:       true

	values: {
		// a DaemonSet so externalTrafficPolicy: Local routes node-locally
		deployment: kind: "DaemonSet"

		ingressClass: enabled: false

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
				version: "v0.8.27"
			}
		}

		logs: {
			general: {level: "INFO", format: "json"}
			access: {
				enabled: true
				format:  "json"
				fields: headers: defaultmode: "keep"
			}
		}

		service: {
			annotations: "metallb.universe.tf/loadBalancerIPs": "192.168.0.128"
			spec: externalTrafficPolicy:                        "Local"
		}
	}
}

// Resolves a client IP to a country for the geoblock plugin.
_geoLookup: schema.#AppRelease & {
	name:      "traefik-geo-lookup"
	namespace: bundle.namespace

	identifierSuffix: false

	let uid = 1000
	let gid = 1000
	let portHTTP = 3000

	let probe = {
		custom:  true
		enabled: true
		spec: httpGet: {path: "/info", port: portHTTP}
	}

	values: {
		controllers: "traefik-geo-lookup": {
			type:     "deployment"
			strategy: "RollingUpdate"
			pod: securityContext: {
				runAsNonRoot: true
				runAsUser:    uid
				runAsGroup:   gid
				supplementalGroups: [568]
				fsGroup: gid
				seccompProfile: type: "RuntimeDefault"
			}
			containers: country: schema.#Hardened & {
				image: {
					repository: "lineofflight/country"
					tag:        "latest@sha256:93b11de55abe44abc511281aea89b2dd53a679b50eab95a814d5fc530d8d0e1b"
				}
				env: PORT: portHTTP
				envFrom: [{secretRef: name: "traefik-geo-lookup"}]
				probes: {
					liveness: probe & {spec: failureThreshold: 6}
					readiness: probe
					startup: probe & {spec: {failureThreshold: 30, periodSeconds: 5}}
				}
			}
		}

		service: "traefik-geo-lookup": {
			controller: "traefik-geo-lookup"
			ports: http: port: portHTTP
		}

		persistence: data: {
			type:       "persistentVolumeClaim"
			accessMode: "ReadWriteOnce"
			size:       "1Gi"
			globalMounts: [{path: "/app/data"}]
		}
	}
}

// Session store for the oidc plugin.
_oidcRedis: schema.#Release & {
	name:       "traefik-oidc-redis"
	namespace:  bundle.namespace
	chart:      "redis-replication"
	version:    "0.17.0"
	sourceName: "ot-helm"

	values: redisReplication: redisSecret: {
		secretName: name
		secretKey:  "password"
	}
}
