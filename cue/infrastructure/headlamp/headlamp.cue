package headlamp

// cSpell:ignore Kanidm pkce

import (
	"strings"
	"github.com/joker9944/k8s-config/schema"
)

// Headlamp forwards each user's id_token to the kube-apiserver, which trusts
// this client's issuer through an AuthenticationConfiguration set in
// nix-config. RBAC below binds the kanidm group, prefixed `oidc:` there.
bundle: schema.#Bundle & {
	namespace: "headlamp"
	needs: ["kanidm"]
	middlewares:     false
	namespaceLabels: schema.#KanidmProvisioningLabel
	repositories: [_repo]
	releases: [_headlamp]
	after: [_kanidmAdmins.out, _kanidmClient.out, _binding]
}

_repo: schema.#HelmRepo & {name: "headlamp", url: "https://kubernetes-sigs.github.io/headlamp/"}

let host = "headlamp.\(schema.#TailnetDomain)"
let pluginsDir = "/headlamp/plugins"

// Prometheus is not listed: the image bundles it as a static plugin.
_plugins: {
	flux: {
		// renovate: datasource=github-releases depName=headlamp-plugin-flux packageName=headlamp-k8s/plugins extractVersion=^flux-(?<version>.+)$
		version: "0.8.0"
		asset:   "headlamp-k8s-flux-\(version).tar.gz"
	}
	"cert-manager": {
		// renovate: datasource=github-releases depName=headlamp-plugin-cert-manager packageName=headlamp-k8s/plugins extractVersion=^cert-manager-(?<version>.+)$
		version: "0.1.1"
		asset:   "headlamp-k8s-cert-manager-\(version).tar.gz"
	}
}

_base: schema.#PinnedImage & {image: {
	repository: "ghcr.io/joker9944/base"
	tag:        "1.0.0@sha256:612a1a68ad367e331c91e745597a79ac1e717bc16b0d06ffdeaeccef8a5e5094"
}}

_headlamp: schema.#Release & {
	name:      "headlamp"
	namespace: bundle.namespace
	chart:     "headlamp"
	// renovate: datasource=helm packageName=headlamp registryUrl=https://kubernetes-sigs.github.io/headlamp/
	version:    "0.46.0"
	sourceName: _repo.name

	"host":  host
	tailnet: true

	values: {
		// The chart binds cluster-admin to its own ServiceAccount by default.
		// Every request carries the user's token, so the pod needs none.
		clusterRoleBinding: create: false

		// Setting any field drops the chart's own defaults; runAsUser and
		// runAsNonRoot still merge in from its values.yaml.
		podSecurityContext: seccompProfile: type: "RuntimeDefault"
		securityContext: schema.#Hardened.securityContext

		config: {
			"pluginsDir": pluginsDir
			oidc: {
				clientID:    _kanidmClient.name
				issuerURL:   _kanidmClient.issuer
				scopes:      strings.Join(_kanidmClient.scopes, ",")
				callbackURL: _kanidmClient.origin
				usePKCE:     true
				secret: create: false
			}
			// The chart only wires -oidc-client-secret for a literal value; the
			// variable is named off its OIDC_* scan so a secretKeyRef stays out of it.
			extraArgs: ["-oidc-client-secret=$(KANIDM_CLIENT_SECRET)"]
		}
		env: [{
			name: "KANIDM_CLIENT_SECRET"
			valueFrom: secretKeyRef: {name: _kanidmClient.secretName, key: "CLIENT_SECRET"}
		}]

		initContainers: [{
			name:            "plugins"
			image:           "\(_base.image.repository):\(_base.image.tag)"
			securityContext: schema.#Hardened.securityContext
			command: ["/bin/sh", "-ec"]
			args: [strings.Join([for n, p in _plugins {
				"curl -fsSL https://github.com/headlamp-k8s/plugins/releases/download/\(n)-\(p.version)/\(p.asset) | tar -xz -C \(pluginsDir)"
			}], "\n")]
			volumeMounts: [{name: "plugins", mountPath: pluginsDir}]
		}]
		volumes: [{name: "plugins", emptyDir: {}}]
		volumeMounts: [{name: "plugins", mountPath: pluginsDir}]

		ingress: {
			enabled:          true
			ingressClassName: _headlamp.ingressClass
			annotations:      _headlamp.ingressAnnotations
			hosts: [{"host": host, paths: [{path: "/", type: "Prefix"}]}]
			tls: [{hosts: [host]}]
		}
	}
}

// ---------------------------------------------------------------------- kanidm

_kanidmAdmins: schema.#KanidmGroup & {name: "headlamp_admins", member: "nyx_admins", ns: bundle.namespace}

_kanidmClient: schema.#KanidmOAuth2Client & {
	name:        "headlamp"
	ns:          bundle.namespace
	displayname: "Headlamp"
	origin:      "https://\(host)/oidc-callback"
	redirectUrl: [origin]
	groups: [_kanidmAdmins]
	scopes: ["openid", "profile", "email", "groups"]
}

// ------------------------------------------------------------------------ rbac

_binding: {
	apiVersion: "rbac.authorization.k8s.io/v1"
	kind:       "ClusterRoleBinding"
	metadata: name: "oidc-\(strings.Replace(_kanidmAdmins.name, "_", "-", -1))"
	roleRef: {apiGroup: "rbac.authorization.k8s.io", kind: "ClusterRole", name: "cluster-admin"}
	subjects: [{apiGroup: "rbac.authorization.k8s.io", kind: "Group", name: "oidc:\(_kanidmAdmins.name)@idm.vonarx.online"}]
}
