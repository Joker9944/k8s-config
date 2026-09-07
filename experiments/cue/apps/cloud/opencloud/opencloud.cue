package opencloud

// cSpell:ignore wopiserver

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "opencloud"
	source:    "apps/base/opencloud"
	extraSecretFiles: ["apps/cloud/opencloud/secrets/opencloud.secret.yaml"]
	// the chart is not published to a registry; Flux tracks the repository
	repositories: [
		schema.#GitRepo & {name: "opencloud", url: "https://github.com/opencloud-eu/helm", branch: "main"},
	]
	releases: [_opencloud]
}

_opencloud: schema.#Release & {
	name:       "opencloud"
	namespace:  "opencloud"
	chart:      "charts/opencloud"
	version:    "" // a git ref, not a chart version
	sourceKind: "GitRepository"
	sourceName: "opencloud"

	host: "cloud-eval.vonarx.online"
	// the chart's own annotationsPreset supplies tls and entrypoints
	ingressPreset: true

	values: {
		global: {
			domain: {
				opencloud: host
				wopi:      "wopiserver.vonarx.online"
				collabora: "office-eval.vonarx.online"
			}
			tls: {enable: true, secretName: "wildcard-vonarx-online-cert"}
			oidc: {
				issuer:     "https://idm.vonarx.online/oauth2/openid/opencloud"
				clientId:   "opencloud"
				accountUrl: "https://idm.vonarx.online/ui/profile"
			}
		}

		keycloak: internal: enabled: false
		postgres: enabled: false

		collabora: {enabled: true, existingSecret: "opencloud-collabora-credentials"}
		onlyoffice: enabled: false

		opencloud: storage: s3: {
			internal: enabled: false
			external: {
				enabled:        true
				endpoint:       "http://garage.garage.svc.cluster.local:3900"
				region:         "nyx"
				existingSecret: "opencloud-s3"
				bucket:         "opencloud"
				createBucket:   false
			}
		}

		ingress: {
			enabled:           true
			annotationsPreset: "traefik"
			annotations:       _opencloud.ingressAnnotations
		}
	}
}
