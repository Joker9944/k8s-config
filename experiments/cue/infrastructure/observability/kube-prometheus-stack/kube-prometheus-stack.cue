package kubeprometheusstack

// cSpell:ignore Kanidm kubeprometheusstack lokiexplore pkce

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "kube-prometheus-stack"
	source:    "infrastructure/base/kube-prometheus-stack"
	secretFiles: ["infrastructure/observability/kube-prometheus-stack/secrets/kube-prometheus-stack.secret.yaml"]
	repositories: [_prometheusCommunity]
	namespaceLabels: {
		// required for node-exporter
		"pod-security.kubernetes.io/audit":   "privileged"
		"pod-security.kubernetes.io/enforce": "privileged"
		"pod-security.kubernetes.io/warn":    "privileged"
	}
	releases: [_kps]
}

_prometheusCommunity: schema.#HelmRepo & {
	name: "prometheus-community"
	url:  "https://prometheus-community.github.io/helm-charts"
}

// TODO pull this stack chart apart and use the individual app charts, with a
// monitoring-apps namespace for Grafana
_kps: schema.#Release & {
	name:       "kube-prometheus-stack"
	namespace:  bundle.namespace
	chart:      "kube-prometheus-stack"
	version:    "81.6.9"
	sourceName: _prometheusCommunity.name
	crds:       true

	// Three ingresses on one chart, on two different chains, so each builds its
	// own annotation set rather than reading the release's single one.
	_internal: (schema.#IngressAnnotations & {
		ns:    namespace
		chain: "chain-network-internal-whitelist"
	}).out
	_public: (schema.#IngressAnnotations & {ns: namespace}).out

	let tlsSecret = "wildcard-vonarx-online-cert"

	values: {
		alertmanager: {
			config: {
				route: receiver: "gotify-joker9944"
				receivers: [
					{name: "null"},
					{
						name: "gotify-joker9944"
						webhook_configs: [{
							send_resolved: false
							url:           "http://gotify-alertmanager-bridge.gotify.svc.cluster.local/webhook"
						}]
					},
				]
			}
			ingress: {
				enabled:     true
				annotations: _internal
				hosts: ["alertmanager.vonarx.online"]
				paths: ["/"]
				tls: [{secretName: tlsSecret, hosts: ["alertmanager.vonarx.online"]}]
			}
		}

		grafana: {
			admin: {
				existingSecret: "grafana-admin"
				userKey:        "username"
				passwordKey:    "password"
			}

			"grafana.ini": {
				server: root_url: "https://grafana.vonarx.online/"

				"auth.generic_oauth": {
					enabled:                    true
					name:                       "Kanidm"
					client_id:                  "grafana"
					scopes:                     "openid,profile,email,groups"
					auth_url:                   "https://idm.vonarx.online/ui/oauth2"
					token_url:                  "https://idm.vonarx.online/oauth2/token"
					api_url:                    "https://idm.vonarx.online/oauth2/openid/grafana/userinfo"
					use_pkce:                   true
					use_refresh_token:          true
					allow_sign_up:              true
					login_attribute_path:       "preferred_username"
					groups_attribute_path:      "groups"
					role_attribute_path:        "contains(grafana_role[*], 'GrafanaAdmin') && 'GrafanaAdmin' || contains(grafana_role[*], 'Admin') && 'Admin' || contains(grafana_role[*], 'Editor') && 'Editor' || 'Viewer'"
					allow_assign_grafana_admin: false
				}

				users: viewers_can_edit: true
			}

			envFromSecret: "grafana-environment"
			plugins: ["grafana-lokiexplore-app"]

			additionalDataSources: [{
				name:   "loki"
				type:   "loki"
				access: "proxy"
				url:    "http://loki-read.loki.svc.cluster.local:3100"
			}]

			ingress: {
				enabled:     true
				annotations: _public
				hosts: ["grafana.vonarx.online"]
				paths: ["/"]
				// the doubled domain is deployed as-is; see /architecture/config-drift.md
				tls: [{secretName: tlsSecret, hosts: ["grafana.vonarx.online.vonarx.online"]}]
			}
		}

		prometheus: {
			prometheusSpec: {
				retention:     "14d"
				retentionSize: "30GB"
				storageSpec: volumeClaimTemplate: spec: {
					storageClassName: "longhorn"
					accessModes: ["ReadWriteOnce"]
					resources: requests: storage: "30Gi"
				}
			}
			ingress: {
				enabled:     true
				annotations: _internal
				hosts: ["prometheus.vonarx.online"]
				paths: ["/"]
				// the doubled domain is deployed as-is; see /architecture/config-drift.md
				tls: [{secretName: tlsSecret, hosts: ["prometheus.vonarx.online.vonarx.online"]}]
			}
		}

		// WORKAROUND both disabled: security prohibits scraping these endpoints
		// directly
		kubeScheduler: enabled:         false
		kubeControllerManager: enabled: false
	}
}
