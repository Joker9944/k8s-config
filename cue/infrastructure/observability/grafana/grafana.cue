@extern(embed)

package grafana

// cSpell:ignore Kanidm lokiexplore mcp pkce

import "github.com/joker9944/k8s-config/schema"

// A leaf: nothing waits on Grafana, so it may wait on kanidm. Inside
// kube-prometheus-stack it sat behind that bundle's wait, which kanidm-cluster
// depends on through volsync.
bundle: schema.#Bundle & {
	namespace: "grafana"
	needs: ["monitoring"]
	extraSecretFiles: ["infrastructure/observability/grafana/secrets/grafana.secret.yaml"]
	repositories: [_repo]
	before: [_dashboards.out]
	releases: [_grafana]
}

// Plaintext dashboard, read from disk at evaluation time. @embed cannot escape
// the package directory, which is why this file lives here.
_labelConformance: _ @embed(file="files/label-conformance.json", type=text)

// Cross-signal: the panels read both stores, so the "belongs to the store the
// panels read" rule that places loki's logs dashboard does not decide this one.
// It lives with Grafana instead.
_dashboards: schema.#ConfigMapFiles & {
	name: "grafana-dashboards"
	ns:   bundle.namespace
	labels: {
		grafana_dashboard:            "1"
		"app.kubernetes.io/name":     "grafana"
		"app.kubernetes.io/instance": "grafana"
	}
	files: "label-conformance.json": _labelConformance
}

_repo: schema.#HelmRepo & {
	name: "grafana-community"
	type: "oci"
	url:  "oci://ghcr.io/grafana-community/helm-charts"
}

let host = "grafana.vonarx.online"

_grafana: schema.#Release & {
	name:      "grafana"
	namespace: bundle.namespace
	chart:     "grafana"
	// renovate: datasource=docker packageName=ghcr.io/grafana-community/helm-charts/grafana
	version:    "14.4.1"
	sourceName: _repo.name

	"host": host

	// HACK the read-only MCP server's service account is created by hand,
	// see grafana-service-account.txt. Grafana provisions datasources,
	// dashboards and plugins but not service accounts or their tokens
	// (https://github.com/grafana/grafana/issues/82987), and with no
	// persistence here the account does not outlive the pod.
	values: {
		admin: {
			existingSecret: "grafana-admin"
			userKey:        "username"
			passwordKey:    "password"
		}

		"grafana.ini": {
			server: root_url: "https://\(host)/"

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
		}

		envFromSecret: "grafana-environment"
		plugins: ["grafana-lokiexplore-app"]

		// kube-prometheus-stack still renders the Prometheus and Alertmanager
		// datasources and its default dashboards; the sidecars collect them, and
		// every other app's dashboards, from any namespace.
		sidecar: {
			dashboards: {
				enabled:         true
				label:           "grafana_dashboard"
				labelValue:      "1"
				searchNamespace: "ALL"
				provider: allowUiUpdates: false
			}
			datasources: {
				enabled:         true
				label:           "grafana_datasource"
				labelValue:      "1"
				searchNamespace: "ALL"
			}
		}

		datasources: "datasources.yaml": {
			apiVersion: 1
			datasources: [{
				name:   "loki"
				type:   "loki"
				access: "proxy"
				url:    "http://loki-gateway.loki.svc.cluster.local"
			}]
		}

		serviceMonitor: enabled: true

		ingress: {
			enabled:     true
			annotations: _grafana.ingressAnnotations
			hosts: [host]
			paths: ["/"]
			tls: [{secretName: "wildcard-vonarx-online-cert", hosts: [host]}]
		}
	}
}
