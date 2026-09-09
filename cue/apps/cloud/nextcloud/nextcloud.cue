package nextcloud

// cSpell:ignore aliasgroups OVERWRITEPROTOCOL

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "nextcloud"
	extraSecretFiles: ["apps/cloud/nextcloud/secrets/nextcloud.secret.yaml"]
	repositories: [
		schema.#HelmRepo & {name: "nextcloud", url: "https://nextcloud.github.io/helm/"},
	]
	before: [_caldavRedirect, _cnpg]
	releases: [_nextcloud]
}

let nextcloudHost = "cloud.vonarx.online"
let collaboraHost = "office.vonarx.online"
let tlsSecret = "wildcard-vonarx-online-cert"

// Clients look for CalDAV/CardDAV at /.well-known; Nextcloud serves them
// elsewhere. Namespace-local, so it is not part of #Middlewares.
_caldavRedirect: {
	apiVersion: "traefik.io/v1alpha1"
	kind:       "Middleware"
	metadata: {name: "caldav-carddav-redirect", namespace: "nextcloud"}
	spec: redirectRegex: {
		permanent:   true
		regex:       "https://(.*)/.well-known/(card|cal)dav"
		replacement: "https://${1}/remote.php/dav/"
	}
}

_cnpg: {
	apiVersion: "postgresql.cnpg.io/v1"
	kind:       "Cluster"
	metadata: {name: "nextcloud-cnpg", namespace: "nextcloud"}
	spec: {
		description: "PostgreSQL Cluster for Nextcloud"
		instances:   3
		imageCatalogRef: {
			apiGroup: "postgresql.cnpg.io"
			kind:     "ClusterImageCatalog"
			name:     "postgresql-standard-trixie"
			major:    16
		}
		storage: {size: "1Gi", storageClass: "longhorn-local-strict"}
		walStorage: {size: "1Gi", storageClass: "longhorn-local-strict"}
		bootstrap: initdb: {database: "nextcloud", owner: "nextcloud"}
		affinity: {enablePodAntiAffinity: true, podAntiAffinityType: "required"}
	}
}

_nextcloud: schema.#Release & {
	name:      "nextcloud"
	namespace: "nextcloud"
	chart:     "nextcloud"
	// renovate: datasource=helm packageName=nextcloud registryUrl=https://nextcloud.github.io/helm/
	version:    "8.0.2"
	sourceName: "nextcloud"

	host: nextcloudHost
	extraMiddlewares: ["caldav-carddav-redirect"]

	// collabora sits behind the plain chain, without the CalDAV redirect
	_collaboraAnnotations: (schema.#IngressAnnotations & {ns: namespace}).out

	values: {
		nextcloud: {
			host: nextcloudHost
			existingSecret: {enabled: true, secretName: "nextcloud-credentials"}
			objectStore: s3: {
				enabled:        true
				port:           3900
				ssl:            false
				region:         "nyx"
				existingSecret: "nextcloud-s3"
				usePathStyle:   true
				secretKeys: {host: "host", accessKey: "accessKey", secretKey: "secretKey", bucket: "bucket"}
			}
			configs: {
				"oidc.config.php": """
					<?php
					$CONFIG = [
					  'allow_local_remote_servers' => true,
					  'user_oidc' => [
					      'use_pkce' => true,
					  ],
					  'allow_user_to_change_display_name' => false,
					  'lost_password_link' => 'disabled',
					];
					"""
				"maintenance.config.php": """
					<?php
					$CONFIG = [
					  'maintenance_window_start' => 1,
					];
					"""
			}
			extraEnv: [
				{name: "TRUSTED_PROXIES", value: schema.#PodCIDR},
				{name: "OVERWRITEPROTOCOL", value: "https"},
			]
		}

		persistence: {enabled: true, size: "2Gi", nextcloudData: enabled: true}

		internalDatabase: enabled: false
		externalDatabase: {
			enabled: true
			type:    "postgresql"
			existingSecret: {
				enabled:     true
				secretName:  "nextcloud-cnpg-app"
				hostKey:     "host"
				usernameKey: "username"
				passwordKey: "password"
				databaseKey: "dbname"
			}
		}

		// the nextcloud chart takes one ingress, not a keyed set
		ingress: {
			enabled:     true
			annotations: _nextcloud.ingressAnnotations
			tls: [{hosts: [nextcloudHost], secretName: tlsSecret}]
		}

		cronjob: enabled: true

		collabora: {
			enabled: true
			collabora: {
				aliasgroups: [{host: "https://\(nextcloudHost):443"}]
				extra_params: "--o:ssl.enable=false --o:ssl.termination=true --o:remote_font_config.url=https://\(nextcloudHost)/apps/richdocuments/settings/fonts.json"
				existingSecret: {enabled: true, secretName: "nextcloud-collabora-credentials"}
				env: [{name: "dictionaries", value: "de_CH en_US"}]
			}
			ingress: {
				enabled:     true
				annotations: _nextcloud._collaboraAnnotations
				hosts: [{host: collaboraHost, paths: [{path: "/", pathType: "Prefix"}]}]
				tls: [{hosts: [collaboraHost], secretName: tlsSecret}]
			}
		}

		redis: {
			enabled: false
			auth: {existingSecret: "nextcloud-redis-credentials", existingSecretPasswordKey: "password"}
			architecture: "standalone"
			master: persistence: enabled: false
		}
	}
}
