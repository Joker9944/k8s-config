package pgadmin

// cSpell:ignore runix

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "pgadmin"
	// the only ingress here is served from the tailnet, so no Traefik middleware
	middlewares: false
	extraSecretFiles: ["apps/utility/pgadmin/secrets/pgadmin.secret.yaml"]
	repositories: [
		schema.#HelmRepo & {name: "runix", url: "https://helm.runix.net"},
	]
	releases: [_pgadmin]
}

// One server entry per CNPG cluster in the fleet.
_server: {
	Name:          string
	Group:         "Servers"
	Host:          "\(_ns)-cnpg-rw.\(_ns).svc.cluster.local"
	Port:          5432
	Username:      _ns
	SSLMode:       "prefer"
	MaintenanceDB: "postgres"
	_ns:           string
}

_pgadmin: schema.#Release & {
	name:      "pgadmin"
	namespace: "pgadmin"
	chart:     "pgadmin4"
	// renovate: datasource=helm packageName=pgadmin4 registryUrl=https://helm.runix.net
	version:    "1.70.4"
	sourceName: "runix"
	interval:   "5m"

	host:    "pgadmin.\(schema.#TailnetDomain)"
	tailnet: true

	values: {
		// The chart routes PGADMIN_DEFAULT_PASSWORD through this Secret and stops
		// generating one of its own. The email has no such path — the chart writes
		// it as a literal — so it is an ordinary value.
		existingSecret: "pgadmin-credentials"
		secretKeys: pgadminPasswordKey: "password"
		env: email:                     "admin@acme.com"

		serverDefinitions: {
			enabled: true
			servers: {
				servarr: _server & {Name: "Servarr", _ns: "servarr"}
			}
		}

		// the pgadmin4 chart takes one ingress, not a keyed set, so the class and
		// annotations #Release computes are spliced in here. The chart gates the
		// TLS secret on its own presence, so the entry carries only the host the
		// operator reads the MagicDNS name from.
		ingress: {
			enabled:          true
			ingressClassName: _pgadmin.ingressClass
			annotations:      _pgadmin.ingressAnnotations
			hosts: [{"host": host, paths: [{path: "/", pathType: "Prefix"}]}]
			tls: [{hosts: [host]}]
		}

		persistentVolume: enabled: false
		networkPolicy: enabled:    false
	}
}
