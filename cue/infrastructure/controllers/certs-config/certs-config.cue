package certsconfig

// cSpell:ignore certsconfig

import (
	"list"
	"github.com/joker9944/k8s-config/schema"
)

bundle: schema.#ConfigBundle & {
	dependsOn: ["cert-manager"]

	// Nothing downstream can serve TLS until these two exist, so the reconcile
	// blocks on them rather than on the Kustomization merely applying.
	healthChecks: [for c in [_wildcardCert, _intermediateCert] {
		apiVersion: c.apiVersion
		kind:       c.kind
		name:       c.metadata.name
		namespace:  c.metadata.namespace
	}]
	secretFiles: ["infrastructure/controllers/certs-config/secrets/cloudflare.secret.yaml"]
	resources: list.Concat([
		[_rootCert, _rootIssuer, _intermediateCert, _intermediateIssuer],
		_bundles,
		_cloudflareIssuers,
		[_wildcardCert],
	])
}

// cert-manager's own namespace holds every private key here; the certificates
// leave it only as the trust bundles below, and as the reflected wildcard.
let ns = "cert-manager"
let email = "postmaster@vonarx.online"

let domain = "vonarx.online"

// --------------------------------------------------------------- the private CA
// A two-tier chain: a long-lived root signs a shorter-lived intermediate, and
// only the intermediate ever issues. /platform/certificates-and-pki.md has why.

_rootCert: {
	apiVersion: "cert-manager.io/v1"
	kind:       "Certificate"
	metadata: {name: "nyx-root-ca", namespace: ns}
	spec: {
		isCA:       true
		commonName: "Nyx Root R1"
		duration:   "19440h" // 810 days
		issuerRef: {group: "cert-manager.io", kind: "Issuer", name: "trust-manager"}
		secretName: "nyx-root-ca-cert"
	}
}

_rootIssuer: {
	apiVersion: "cert-manager.io/v1"
	kind:       "Issuer"
	metadata: {name: "nyx-root-ca", namespace: ns}
	spec: ca: secretName: _rootCert.spec.secretName
}

_intermediateCert: {
	apiVersion: "cert-manager.io/v1"
	kind:       "Certificate"
	metadata: {name: "nyx-intermediate-ca", namespace: ns}
	spec: {
		isCA:       true
		commonName: "Nyx Intermediate R1"
		duration:   "6480h" // 270 days
		issuerRef: {group: "cert-manager.io", kind: "Issuer", name: _rootIssuer.metadata.name}
		secretName: "nyx-intermediate-ca-cert"
	}
}

// The ClusterIssuer #NamespaceCert names, which is what makes the private CA
// reachable from any namespace.
_intermediateIssuer: {
	apiVersion: "cert-manager.io/v1"
	kind:       "ClusterIssuer"
	metadata: name: "nyx-intermediate-ca"
	spec: ca: secretName: _intermediateCert.spec.secretName
}

// ------------------------------------------------------------- trust bundles
// trust-manager copies these into every namespace carrying the matching label,
// which is how a pod gets the CA without the CA's key. The public variant adds
// the system roots, for a client that has to reach both inside and outside.

_bundles: [for bundleName, useDefaults in {
	"nyx-ca-cert-bundle":        false
	"public-nyx-ca-cert-bundle": true
} {
	apiVersion: "trust.cert-manager.io/v1alpha1"
	kind:       "Bundle"
	metadata: name: bundleName
	spec: {
		sources: list.Concat([
			[if useDefaults {{useDefaultCAs: true}}],
			[for c in [_intermediateCert, _rootCert] {
				secret: {"name": c.spec.secretName, key: "ca.crt"}
			}],
		])
		target: {
			secret: key: "ca.crt"
			namespaceSelector: matchLabels: "vonarx.online/distribute-\(bundleName)": "true"
		}
	}
}]

// ------------------------------------------------------------ the public cert
// Let's Encrypt over DNS-01, because the wildcards cannot be validated by HTTP.

_cloudflareIssuers: [for issuerName, acmeServer in {
	"cloudflare-production": "https://acme-v02.api.letsencrypt.org/directory"
	"cloudflare-staging":    "https://acme-staging-v02.api.letsencrypt.org/directory"
} {
	apiVersion: "cert-manager.io/v1"
	kind:       "ClusterIssuer"
	metadata: name: issuerName
	spec: acme: {
		"email": email
		privateKeySecretRef: name: "\(issuerName)-account-key"
		server: acmeServer
		solvers: [{dns01: cloudflare: {
			apiTokenSecretRef: {name: "cloudflare-api-token", key: "token"}
			"email": email
		}}]
	}
}]

// One certificate for every host the fleet serves. reflector copies it into each
// namespace that needs it, which is why the ingresses all name the same secret.
_wildcardCert: {
	apiVersion: "cert-manager.io/v1"
	kind:       "Certificate"
	// The name is the domain with dots replaced, not derived from it: every
	// ingress in the fleet names `<this>-cert` literally.
	metadata: {name: "wildcard-vonarx-online", namespace: ns}
	spec: {
		dnsNames: [domain, "*.\(domain)", "*.s3.\(domain)", "*.web.\(domain)"]
		issuerRef: {group: "cert-manager.io", kind: "ClusterIssuer", name: "cloudflare-production"}
		secretName: "\(_wildcardCert.metadata.name)-cert"
		secretTemplate: annotations: {
			"reflector.v1.k8s.emberstack.com/reflection-allowed":      "true"
			"reflector.v1.k8s.emberstack.com/reflection-auto-enabled": "true"
		}
	}
}
