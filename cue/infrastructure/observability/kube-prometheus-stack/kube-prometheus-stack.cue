package kubeprometheusstack

// cSpell:ignore Kanidm kubeprometheusstack lokiexplore mcp Mem nodememoryhighutilization pkce runbook zfs

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#Bundle & {
	namespace: "kube-prometheus-stack"
	extraSecretFiles: [
		"infrastructure/observability/kube-prometheus-stack/secrets/kube-prometheus-stack.secret.yaml",
		"infrastructure/observability/kube-prometheus-stack/secrets/joker9944.secret.yaml",
	]
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
	name:      "kube-prometheus-stack"
	namespace: bundle.namespace
	chart:     "kube-prometheus-stack"
	// renovate: datasource=helm packageName=kube-prometheus-stack registryUrl=https://prometheus-community.github.io/helm-charts
	version:    "90.0.0"
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

	// The bridge picks its Gotify application from a ?token= on the webhook URL,
	// so the URL is a credential. url_file keeps it out of the artifact: the
	// operator models the field and alertmanager re-reads the file per
	// notification, so rotating the Secret needs no restart.
	let gotifyURLSecret = "alertmanager-gotify-joker9944-url"

	values: {
		alertmanager: {
			alertmanagerSpec: secrets: [gotifyURLSecret]

			config: {
				route: receiver: "gotify-joker9944"
				receivers: [
					{name: "null"},
					{
						name: "gotify-joker9944"
						webhook_configs: [{
							send_resolved: false
							url_file:      "/etc/alertmanager/secrets/\(gotifyURLSecret)/url"
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

		// HACK the read-only MCP server's service account is created by hand,
		// see grafana-service-account.txt. Grafana provisions datasources,
		// dashboards and plugins but not service accounts or their tokens
		// (https://github.com/grafana/grafana/issues/82987), and with no
		// persistence here the account does not outlive the pod.
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
				url:    "http://loki-gateway.loki.svc.cluster.local"
			}]

			ingress: {
				enabled:     true
				annotations: _public
				hosts: ["grafana.vonarx.online"]
				paths: ["/"]
				tls: [{secretName: tlsSecret, hosts: ["grafana.vonarx.online"]}]
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
				tls: [{secretName: tlsSecret, hosts: ["prometheus.vonarx.online"]}]
			}
		}

		// The stock NodeMemoryHighUtilization reads node_memory_MemAvailable_bytes,
		// which Linux computes without the ZFS ARC: mother caches ~54 of its 62 GiB
		// there and so reports 95% used at 11% real usage. `customRules` reaches
		// only `for` and `severity`, never the expression, so correcting it means
		// replacing the rule. ARC is reclaimable down to arc_c_min; the `or` arm
		// supplies 0 on the three nodes that have no ARC, keeping one rule for the
		// whole fleet.
		defaultRules: disabled: NodeMemoryHighUtilization: true
		additionalPrometheusRulesMap: "node-exporter-zfs": groups: [{
			name: "node-exporter-zfs"
			rules: [{
				alert: "NodeMemoryHighUtilization"
				expr: """
					100 - (
					  (
					    node_memory_MemAvailable_bytes{job="node-exporter"}
					    + (
					        clamp_min(node_zfs_arc_size{job="node-exporter"} - node_zfs_arc_c_min{job="node-exporter"}, 0)
					        or node_memory_MemAvailable_bytes{job="node-exporter"} * 0
					      )
					  ) / node_memory_MemTotal_bytes{job="node-exporter"} * 100
					) > 90
					"""
				"for": "15m"
				labels: severity: "warning"
				annotations: {
					summary:     "Host is running out of memory."
					runbook_url: "https://runbooks.prometheus-operator.dev/runbooks/node/nodememoryhighutilization"
					description: #"Memory is filling up at {{ $labels.instance }}, has been above 90% for the last 15 minutes, is currently at {{ printf "%.2f" $value }}%. Reclaimable ZFS ARC already counts as available."#
				}
			}]
		}]

		// the node exporter is a DaemonSet; without this a reserved node reports
		// no metrics at all
		"prometheus-node-exporter": tolerations: [schema.#Reserved.any]

		// WORKAROUND both disabled: security prohibits scraping these endpoints
		// directly
		kubeScheduler: enabled:         false
		kubeControllerManager: enabled: false

		// k3s runs kube-proxy inside the agent process, so nothing carries the
		// k8s-app: kube-proxy label the chart's Service selects on. With no
		// endpoints the target never exists and KubeProxyDown, an absent()
		// rule, fires forever. Naming the nodes builds the Endpoints by hand.
		// Requires metrics-bind-address=0.0.0.0 on the k3s agents from
		// nix-config; the 127.0.0.1 default is unreachable from the Prometheus
		// pod.
		kubeProxy: endpoints: [
			"192.168.0.21",
			"192.168.0.22",
			"192.168.0.23",
			"192.168.0.24",
		]
	}
}
