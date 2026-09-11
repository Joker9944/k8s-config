package opencloud

// cSpell:ignore decomposedfs decomposeds

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "opencloud"
	extraSecretFiles: ["apps/cloud/opencloud/secrets/opencloud.secret.yaml"]
	repositories: [_repo]
	before: [_ingress, _collaboraIngress]
	releases: [_opencloud]
}

// opencloud-eu/helm was archived in favour of a paid offering; this is the
// community fork that carried on, published as an OCI artifact rather than a
// chart index.
_repo: schema.#HelmRepo & {
	name: "opencloud"
	type: "oci"
	url:  "oci://ghcr.io/tim-herbie/opencloud-helm"
}

let host = "cloud-eval.vonarx.online"
let collaboraHost = "office-eval.vonarx.online"
let tlsSecret = "wildcard-vonarx-online-cert"

// The chart builds its ingress tls secretName as `<global.tls.secretName>-opencloud`
// and `-collabora`, which no single shared wildcard can satisfy. Its ingress is
// switched off and the two objects written here instead, so the fleet keeps one
// certificate. The service names and ports are the chart's.
_ingressFor: {
	name:    string
	svc:     string
	svcPort: int
	fqdn:    string

	out: {
		apiVersion: "networking.k8s.io/v1"
		kind:       "Ingress"
		metadata: {
			"name":      name
			namespace:   bundle.namespace
			annotations: _opencloud.ingressAnnotations
		}
		spec: {
			tls: [{hosts: [fqdn], secretName: tlsSecret}]
			rules: [{
				"host": fqdn
				http: paths: [{
					path:     "/"
					pathType: "Prefix"
					backend: service: {name: svc, port: number: svcPort}
				}]
			}]
		}
	}
}

_ingress: (_ingressFor & {
	name: "opencloud", svc: "opencloud-opencloud", svcPort: 9200, fqdn: host
}).out

_collaboraIngress: (_ingressFor & {
	name: "opencloud-collabora", svc: "opencloud-collabora", svcPort: 9980, fqdn: collaboraHost
}).out

_opencloud: schema.#Release & {
	name:      "opencloud"
	namespace: bundle.namespace
	chart:     "opencloud"
	// renovate: datasource=docker packageName=ghcr.io/tim-herbie/opencloud-helm/opencloud
	version:    "3.0.0"
	sourceName: _repo.name

	"host": host

	values: {
		global: {
			domain: {
				opencloud: host
				oidc:      "idm.vonarx.online"
				collabora: collaboraHost
			}
			// the ingresses above carry the tls block
			tls: enabled: false
		}

		ingress: enabled: false

		oidc: {
			issuerUrl:  "https://idm.vonarx.online/oauth2/openid/opencloud"
			clientId:   "opencloud"
			accountUrl: "https://idm.vonarx.online/ui/profile"
		}

		collabora: {
			enabled:        true
			existingSecret: "opencloud-collabora-credentials"
			resources: {
				requests: {cpu: "100m", memory: "256Mi"}
				limits: memory: "2Gi"
			}
		}

		tika: resources: {
			requests: {cpu: "100m", memory: "512Mi"}
			limits: memory: "1500Mi"
		}

		opencloud: {
			// every certificate on the path is real
			insecure:       false
			existingSecret: "opencloud-admin"

			// The chart otherwise generates these with `lookup` + randAlphaNum,
			// which re-rolls whenever the lookup comes back empty. storageUsersMountID
			// in particular is what every stored file reference is resolved against.
			initSecrets: existingSecret: "opencloud-init"

			// Must not contain "idp": the chart reads that as "external LDAP too"
			// and points the LDAP settings at a server this cluster does not run.
			// The built-in IDM stores the accounts kanidm autoprovisions.
			excludeServices: []

			oidc: scope: "openid profile email groups_names roles"

			// The kubelet kills at 30s and storage-users defaults its flush window
			// to the same 30, which races. The chart exposes no
			// terminationGracePeriodSeconds, so give the flush the slack instead.
			env: [
				{name: "STORAGE_USERS_GRACEFUL_SHUTDOWN_TIMEOUT", value: "20"},
			]

			storage: {
				mode:         "s3" // the chart maps this to the decomposeds3 driver
				systemDriver: "decomposed"
				s3: {
					enabled: true
					external: {
						endpoint:       "http://garage.garage.svc.cluster.local:3900"
						region:         "nyx"
						existingSecret: "opencloud-s3"
						bucket:         "opencloud"
					}
				}
			}

			// decomposeds3 keeps the blobs in garage; this volume holds the
			// decomposedfs metadata, the IDM and the search index.
			// TODO volsync — a PVC cannot gain a dataSourceRef after creation, so
			// adding backups means recreating this volume.
			persistence: data: {size: "10Gi", storageClass: "longhorn"}

			resources: {
				requests: {cpu: "128m", memory: "512Mi"}
				limits: memory: "4Gi"
			}
		}
	}
}
