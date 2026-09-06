package schema

import (
	"encoding/yaml"
	"list"
	"strings"
	fluxHelm "github.com/fluxcd/helm-controller/api/v2"
	fluxSource "github.com/fluxcd/source-controller/api/v1"
)

// The Traefik annotations an ingress carries. The middleware reference is
// computed from the namespace it is given, which is what stops an ingress from
// naming another namespace's middleware. A chart with more than one ingress
// (nextcloud) builds a second instance rather than writing the string.
#IngressAnnotations: {
	ns:    string
	chain: #Chain | *"chain-country-whitelist"
	extra: [...string] | *[]
	bare: string | *""

	// opencloud's chart writes the tls and entrypoint annotations itself, from
	// its own `annotationsPreset: traefik`, and duplicating them is a conflict.
	preset: bool | *false

	_first: [if bare != "" {bare}, chain][0]

	out: {
		if !preset {
			"traefik.ingress.kubernetes.io/router.tls":         "true"
			"traefik.ingress.kubernetes.io/router.entrypoints": "websecure"
		}
		"traefik.ingress.kubernetes.io/router.middlewares": strings.Join([
			for m in list.Concat([[_first], extra]) {"\(ns)-\(m)@kubernetescrd"},
		], ",")
	}
}

// One HelmRelease. Typed against helm-controller's own Go API, so the whole
// Flux surface is available and anything outside it is a build error. Chart
// coordinates are parameters, because most of the fleet outside apps/ runs a
// foreign chart. For the bjw-s app-template use #AppRelease.
#Release: {
	name:      string
	namespace: string

	chart:      string
	version:    string // "" for a source that carries no chart version
	sourceKind: "HelmRepository" | "GitRepository" | *"HelmRepository"
	sourceName: string
	interval:   string | *"30m"

	// Ingress wiring. The middleware reference is computed, never written by
	// the caller, so a release cannot name another namespace's middleware.
	// Where the annotations land is the chart's business: #AppRelease places
	// them, a foreign chart splices `ingressAnnotations` at its own path.
	host:       string | *"" // "" means no ingress
	ingressKey: string | *name
	chain:      #Chain | *"chain-country-whitelist"
	extraMiddlewares: [...string] | *[]

	// The sanctioned exception, for a release that sits behind a single
	// middleware instead of a chain and so skips the rate limit, the secure
	// headers and compression. Naming it here rather than widening #Chain keeps
	// every such release findable with grep. qbittorrent is the only user.
	bareMiddleware: string | *""

	// The preset every CRD-shipping chart in the fleet carries, byte-identical
	// across all ten of them: Helm owns the CRD lifecycle and a failed install or
	// upgrade is retried three times.
	crds: bool | *false
	_lifecycle: {"crds": "CreateReplace", remediation: retries: 3}

	secretValuesName: string | *""
	values: {...}

	// blocky-redis is the only release in the fleet that ships no values at all,
	// and CUE cannot tell an unset struct from an empty one.
	hasValues: bool | *true

	ingressPreset: bool | *false
	ingressAnnotations: (#IngressAnnotations & {
		ns:      namespace
		"chain": chain
		extra:   extraMiddlewares
		bare:    bareMiddleware
		preset:  ingressPreset
	}).out

	out: fluxHelm.#HelmRelease & {
		apiVersion: "helm.toolkit.fluxcd.io/v2"
		kind:       "HelmRelease"
		metadata: {"name": name, "namespace": namespace}
		spec: {
			"interval": interval
			// quoted so the label does not bind `chart` and shadow the field above
			"chart": spec: {
				"chart":    chart
				"interval": interval
				if version != "" {"version": version}
				sourceRef: {kind: sourceKind, name: sourceName, "namespace": namespace}
			}
			if crds {
				install: _lifecycle
				upgrade: _lifecycle
			}
			if secretValuesName != "" {
				valuesFrom: [{kind: "Secret", name: secretValuesName}]
			}
			if hasValues {"values": values}
		}
	}
}

// A release from the bjw-s app-template chart, which is what every workload in
// apps/ runs. Adds the chart's own conventions: the identifier suffix and the
// keyed ingress the middleware annotations are placed into.
#AppRelease: {
	#Release

	chart:      "app-template"
	version:    string | *"4.6.2"
	sourceName: "bjw-s"

	// Brought into lexical scope so the values block can read them; CUE resolves
	// references by declaration, not by embedding, so the constraints still come
	// from #Release above.
	host:               _
	ingressKey:         _
	ingressAnnotations: _

	// The identifier suffix is on for every app-template release in the fleet
	// except traefik-geo-lookup. Turning it on there renames its Deployment and
	// Service, so the exception is named here rather than fixed in passing.
	identifierSuffix: bool | *true

	// open at every level a constraint is added: a definition closes what it
	// touches, and these are the chart's conventions, not its whole schema
	values: {
		if identifierSuffix {
			global: {alwaysAppendIdentifierToResourceName: true, ...}
		}
		if host != "" {
			ingress: (ingressKey): {annotations: ingressAnnotations, ...}
		}
		...
	}
}

// A namespace and everything shared inside it: the HelmRepository and the
// Traefik middleware set, installed once regardless of how many releases live
// there. Replaces manifests/namespace.yaml, kustomization.yaml, and the
// bjw-s-helm-repository / common-middlewares / common-kustomizeconfig components.
// A chart source. The namespace is supplied by the bundle, so a call site names
// only the repository.
#HelmRepo: {
	name:     string
	ns:       string | *"" // supplied by #Bundle
	url:      string
	interval: string | *"5m"

	out: fluxSource.#HelmRepository & {
		apiVersion: "source.toolkit.fluxcd.io/v1"
		kind:       "HelmRepository"
		metadata: {"name": name, namespace: ns}
		spec: {"interval": interval, "url": url}
	}
}

#GitRepo: {
	name:     string
	ns:       string | *"" // supplied by #Bundle
	url:      string
	interval: string | *"5m"

	// Exactly one of the two. Sentinels rather than optional fields, because
	// referencing an unset optional is itself an error in CUE.
	branch: string | *""
	tag:    string | *""

	// The ignore rules source-controller applies before it archives the clone,
	// so a repository that ships one chart does not ship the whole tree.
	ignore: string | *""

	out: fluxSource.#GitRepository & {
		apiVersion: "source.toolkit.fluxcd.io/v1"
		kind:       "GitRepository"
		metadata: {"name": name, namespace: ns}
		spec: {
			"interval": interval
			"url":      url
			ref: {
				if branch != "" {"branch": branch}
				if tag != "" {"tag": tag}
			}
			if ignore != "" {"ignore": ignore}
		}
	}
}

#Bundle: {
	namespace: string

	// The element type is what a release renders, not #Release itself: a closed
	// definition rejects the fields a derived one adds, so naming #Release here
	// would make #AppRelease unusable in a bundle. The house constraints live in
	// those definitions, and this is the only thing #Bundle reads.
	releases: [...{out: fluxHelm.#HelmRelease, ...}]

	// The Traefik middleware set. A bundle with no ingress does not install it.
	middlewares: bool | *true

	// An in-cluster wildcard certificate off the private CA, for a workload that
	// serves TLS to the ingress controller rather than plain HTTP.
	namespaceCert: bool | *false

	// Chart sources, defaulting to the bjw-s repository every app-template
	// release needs. A bundle on a foreign chart replaces the list.
	repositories: [...{ns?: string, ...}] | *[#HelmRepo & {
		name: "bjw-s", url: "https://bjw-s-labs.github.io/helm-charts"
	}]
	before: [...] | *[] // emitted between the namespace and the releases
	after: [...] | *[]  // emitted after the releases

	// SOPS Secret manifests, module-relative. The render step copies them
	// verbatim; ciphertext never passes through CUE. See
	// /workflows/secrets-sops.md.
	secretFiles: [...string] | *[]

	// Migration bookkeeping: the kustomize overlay this bundle replaces, read
	// by gate.py. "" means not yet ported. Goes away with apps/base/.
	source: string | *""

	// Pod Security admission levels and the like. Seven namespaces in the fleet
	// carry one; the rest render a bare Namespace.
	namespaceLabels: [string]: string

	_ns: {
		apiVersion: "v1"
		kind:       "Namespace"
		metadata: {
			name: namespace
			if len(namespaceLabels) > 0 {labels: namespaceLabels}
		}
	}

	_repos: [for r in repositories {(r & {ns: namespace}).out}]

	_mw: #Middlewares & {ns: namespace}
	_cert: #NamespaceCert & {ns: namespace}

	out: list.Concat([
		[_ns],
		before,
		[for r in releases {r.out}],
		after,
		_repos,
		if namespaceCert {[_cert.out]},
		if !namespaceCert {[]},
		if middlewares {_mw.out},
		if !middlewares {[]},
	])
}

// A cluster singleton: resources that configure something already installed.
// No namespace of its own, no chart and no releases, which is why
// infrastructure/nyx/config/ has no base/ half — there was nothing to reuse.
#ConfigBundle: {
	resources: [...]

	// SOPS Secret manifests, module-relative, on the same terms as #Bundle's.
	secretFiles: [...string] | *[]

	// Migration bookkeeping, read by gate.py. Goes away with the kustomize tree.
	source: string | *""

	out: resources
}

// A tier: one CUE package, one render, one OCI artifact. Collects the bundles
// its workload packages export.
#Tier: {
	// Constrained by what this definition reads rather than by #Bundle, which is
	// closed and would reject a #ConfigBundle outright.
	bundles: [string]: {
		out: [...]
		secretFiles: [...string]
		source: string
		...
	}

	rendered: {
		for k, b in bundles {(k): yaml.MarshalStream(b.out)}
	}

	// The registry gate.py reads, so the script carries no per-app knowledge.
	// Goes away with apps/base/.
	gateMeta: {
		for k, b in bundles {
			(k): {source: b.source, secretFiles: b.secretFiles}
		}
	}
}
