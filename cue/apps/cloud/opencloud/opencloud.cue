package opencloud

// cSpell:ignore decomposedfs decomposeds

import (
	"encoding/yaml"
	"strings"

	"github.com/joker9944/k8s-config/schema"
)

bundle: schema.#Bundle & {
	namespace: "opencloud"
	// kanidm's LDAPS certificate chains to the private CA; trust-manager writes
	// the bundle here for the volume the postRenderer mounts.
	namespaceLabels: "vonarx.online/distribute-nyx-ca-cert-bundle": "true"
	extraSecretFiles: [
		"apps/cloud/opencloud/secrets/opencloud.secret.yaml",
		"apps/cloud/opencloud/secrets/opencloud-ldap.secret.yaml",
	]
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

let host = "cloud.vonarx.online"
let oidcHost = "idm.vonarx.online"
let collaboraHost = "office.vonarx.online"
let tlsSecret = "wildcard-vonarx-online-cert"
let kanidmBaseDN = "dc=idm,dc=vonarx,dc=online"

// HACK The desktop client does not support webfinger yet so we use that client id
// for all clients.
//
// kanidm mints a per-client issuer URL, and OpenCloud validates every token
// against exactly one issuer, so all four apps have to authenticate as the same
// client. The webfinger service is what overrides the vendor-fixed client_id the
// desktop and mobile apps ship with; the key is read last, so it wins over the
// WEB_OIDC_CLIENT_ID the chart emits.
let clientId = strings.ToLower("OpenCloudDesktop")

// Scopes decode as a list, so these are comma-separated — the space-separated
// form the OpenCloud docs show lands as one element holding the whole string.
// Only the sync clients ask for offline_access.
let webfingerScopes = {
	web:     "openid,profile,email,groups_name,roles"
	desktop: "openid,profile,email,groups_name,roles,offline_access"
	android: desktop
	ios:     desktop
}

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
				oidc:      oidcHost
				collabora: collaboraHost
			}
			tls: enabled: true
		}

		ingress: enabled: false

		oidc: {
			issuerUrl:  "https://\(oidcHost)/oauth2/openid/\(clientId)"
			"clientId": clientId
			accountUrl: "https://\(oidcHost)/ui/profile"
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

		monitoring: enabled: true

		opencloud: {
			// every certificate on the path is real
			insecure:       false
			existingSecret: "opencloud-admin"

			// The chart otherwise generates these with `lookup` + randAlphaNum,
			// which re-rolls whenever the lookup comes back empty. storageUsersMountID
			// in particular is what every stored file reference is resolved against.
			initSecrets: existingSecret: "opencloud-init"

			// Excluding "idp" is the chart's switch for external user management:
			// only then does it render the LDAP env block. "idm" is the built-in
			// LDAP server that kanidm replaces; the chart's gate keys on "idp" alone.
			excludeServices: ["idp", "idm"]

			// User state lives only in kanidm, read over LDAPS. The server is
			// read-only — dn=token binds with an api token — hence no
			// autoprovisioning, write-backs, referential integrity or disable
			// attribute.
			proxyAutoprovisionAccounts: false
			ldapServerWriteEnabled:     false
			graphLdapRefintEnabled:     false
			ldap: {
				uri:       "ldaps://kanidm-ldaps.kanidm.svc.cluster.local:636"
				insecure:  false
				bindDN:    "dn=token"
				secretRef: "opencloud-ldap-bind"
				user: {baseDN: kanidmBaseDN, schema: id: "uuid"}
				group: {baseDN: kanidmBaseDN, createBaseDN: kanidmBaseDN, schema: id: "uuid"}
				disableUserMechanism: "none"
			}

			// WEB_OIDC_SCOPE, read by the web service itself, so space-separated.
			// kanidm has no groups_names: the claim is gated on groups_name.
			oidc: scope: "openid profile email groups_name roles"

			env: [
				// The kubelet kills at 30s and storage-users defaults its flush window
				// to the same 30, which races. The chart exposes no
				// terminationGracePeriodSeconds, so give the flush the slack instead.
				{name: "STORAGE_USERS_GRACEFUL_SHUTDOWN_TIMEOUT", value: "20"},

				// The chart's LDAP block fixes the objectclasses at OpenCloud's
				// OpenLDAP defaults; kanidm presents person and group.
				{name: "OC_LDAP_USER_OBJECTCLASS", value: "person"},
				{name: "OC_LDAP_GROUP_OBJECTCLASS", value: "group"},
				// Mounted by the postRenderer below.
				{name: "OC_LDAP_CACERT", value: "/etc/opencloud/ldap-ca/ca.crt"},

				for platform, scopes in webfingerScopes
				for e in [
					{name: "WEBFINGER_\(strings.ToUpper(platform))_OIDC_CLIENT_ID", value: clientId},
					{name: "WEBFINGER_\(strings.ToUpper(platform))_OIDC_CLIENT_SCOPES", value: scopes},
				] {e},
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
			// decomposedfs metadata and the search index.
			// TODO volsync — a PVC cannot gain a dataSourceRef after creation, so
			// adding backups means recreating this volume.
			persistence: data: {size: "10Gi", storageClass: "longhorn"}

			resources: {
				requests: {cpu: "128m", memory: "512Mi"}
				limits: memory: "4Gi"
			}
		}
	}

	// The chart has no extra-volume knob, so the CA for the LDAPS hop is
	// patched in after rendering.
	postRenderers: [{kustomize: patches: [{patch: yaml.Marshal({
		apiVersion: "apps/v1"
		kind:       "Deployment"
		metadata: name: "opencloud-opencloud"
		spec: template: {
			spec: {
				containers: [{
					name: "opencloud"
					volumeMounts: [{name: "ldap-ca", mountPath: "/etc/opencloud/ldap-ca", readOnly: true}]
				}]
				volumes: [{name: "ldap-ca", secret: secretName: "nyx-ca-cert-bundle"}]
			}}
	})
	}]}]
}
