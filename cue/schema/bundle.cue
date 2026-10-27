package schema

import (
	"encoding/yaml"
	"list"
	"strings"
	fluxHelm "github.com/fluxcd/helm-controller/api/v2"
	fluxKustomize "github.com/fluxcd/kustomize-controller/api/v1"
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

	out: {
		"traefik.ingress.kubernetes.io/router.tls":         "true"
		"traefik.ingress.kubernetes.io/router.entrypoints": "websecure"
		"traefik.ingress.kubernetes.io/router.middlewares": strings.Join([
			for m in list.Concat([[chain], extra]) {"\(ns)_\(m)@kubernetescrd"},
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

	// Helm owns the CRD lifecycle. Only for a chart with a real Helm `crds/`
	// directory — a chart that renders its CRDs as ordinary templates
	// (cert-manager, cnpg, volsync, metallb) never reaches this code path, so
	// setting it there is a lie.
	crds: bool | *false

	// An upgrade failure rolls back and retries. Because a non-zero count also
	// flips remediateLastFailure, the release ends on the last working revision
	// rather than on the broken one. Install remediation is deliberately left
	// off: there it is an uninstall, and blocky's and gotify's Postgres Clusters
	// are Helm-managed, carry no resource-policy, and have no off-cluster copy.
	upgradeRetries: int | *3

	// Ceilings on readiness, not delays: helm-controller waits for the chart's
	// resources before judging the action. Install is generous because a restore
	// bootstrap populates a PVC inside the install, and because upgradeRetries
	// does not apply there — a hit install timeout is terminal until the spec
	// changes or someone forces a reconcile.
	timeout:        string | *"10m"
	installTimeout: string | *"60m"

	// The volsync repositories this release backs up to. Declaring one is what
	// ships its credential Secret, so the two cannot drift apart.
	backups: [...{secretFile: string, secretName: string, out: {...}, ...}] | *[]

	values: {...}

	// blocky-redis is the only release in the fleet that ships no values at all,
	// and CUE cannot tell an unset struct from an empty one.
	hasValues: bool | *true

	// Kustomize patches applied after Helm rendering, for what a chart exposes
	// no knob for.
	postRenderers: [...] | *[]

	ingressAnnotations: (#IngressAnnotations & {
		ns:      namespace
		"chain": chain
		extra:   extraMiddlewares
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
			"timeout": timeout
			install: {
				"timeout": installTimeout
				if crds {"crds": "CreateReplace"}
			}
			// Guarded as a whole: longhorn sets neither, and an empty struct cannot
			// resolve against the field's `null | {...}` disjunction.
			if crds || upgradeRetries > 0 {
				upgrade: {
					if crds {"crds": "CreateReplace"}
					if upgradeRetries > 0 {remediation: retries: upgradeRetries}
				}
			}
			if hasValues {"values": values}
			if len(postRenderers) > 0 {"postRenderers": postRenderers}
		}
	}
}

// renovate: datasource=helm packageName=app-template registryUrl=https://bjw-s-labs.github.io/helm-charts
_appTemplateVersion: "5.3.0"

// A release from the bjw-s app-template chart, which is what every workload in
// apps/ runs. Adds the chart's own conventions: the identifier suffix and the
// keyed ingress the middleware annotations are placed into.
#AppRelease: {
	#Release

	chart:      "app-template"
	version:    string | *_appTemplateVersion
	sourceName: "bjw-s"

	// Brought into lexical scope so the values block can read them; CUE resolves
	// references by declaration, not by embedding, so the constraints still come
	// from #Release above.
	host:               _
	ingressKey:         _
	ingressAnnotations: _
	backups:            _

	// open at every level a constraint is added: a definition closes what it
	// touches, and these are the chart's conventions, not its whole schema
	values: {
		global: {alwaysAppendIdentifierToResourceName: true, ...}
		if host != "" {
			ingress: (ingressKey): {annotations: ingressAnnotations, ...}
		}
		if len(backups) > 0 {
			rawResources: {for b in backups {b.out}}
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

	// An OCI registry is a chart source with no index to poll: the release names
	// a chart and a version, and source-controller resolves it as an artifact.
	// source-controller requires the url to carry the oci:// scheme to match.
	type: "default" | "oci" | *"default"

	out: fluxSource.#HelmRepository & {
		apiVersion: "source.toolkit.fluxcd.io/v1"
		kind:       "HelmRepository"
		metadata: {"name": name, namespace: ns}
		spec: {
			"interval": interval
			"url":      url
			if type != "default" {"type": type}
		}
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

// What one bundle needs from another, named by the thing provided rather than
// by the provider. A closed enum, so a mistyped need is a build error instead
// of a Kustomization waiting forever on a name nobody owns; one provider per
// capability, so moving a provider between tiers touches no consumer.
//
// A capability is something whose absence fails the apply — in practice a CRD.
// Runtime coupling is not a capability: a PVC on a StorageClass that does not
// exist yet stays Pending and binds later, so storage is deliberately absent
// here. Declaring it would make traefik need longhorn, which needs traefik.
//
// The graph these build is documented in /architecture/capability-graph.md,
// which is also where the cycle hazards live — nothing here detects one.
#Capability: "ingress" | "certificate" | "ingress-certificate" |
	"load-balancer" | "load-balancer-pool" | "redis" | "block-storage" |
	"postgres" | "volsync" | "monitoring" | "object-storage" | "log-sink"

_provider: [#Capability]: string
_provider: {
	ingress:               "traefik"               // Middleware CRD
	certificate:           "cert-manager"          // Certificate CRD
	"ingress-certificate": "certs-config"          // the wildcard cert and the intermediate CA
	"load-balancer":       "metallb"               // IPAddressPool and L2Advertisement CRDs
	"load-balancer-pool":  "metallb-config"        // the pool Traefik's Service draws from
	redis:                 "redis-operator"        // RedisFailover CRD
	"block-storage":       "longhorn"              // VolumeSnapshotClass, via the Kustomizations it creates
	postgres:              "cnpg"                  // Cluster CRD and the barman plugin
	volsync:               "volsync"               // ReplicationSource and Destination CRDs
	monitoring:            "kube-prometheus-stack" // ServiceMonitor CRD and the scrape classes
	"object-storage":      "garage"
	"log-sink":            "loki"
}

// The edges a bundle contributes: what it declares, plus what its own fields
// already imply. Deduplicated through a struct, because a capability can be
// both needed explicitly and inferred.
_edges: {
	needs: [...#Capability]
	inferred: [string]: bool

	_set: {
		for c in needs {(_provider[c]): true}
		inferred
	}
	out: [for n, _ in _set {n}]
}

#Bundle: {
	namespace: string

	// The element type is what a release renders, not #Release itself: a closed
	// definition rejects the fields a derived one adds, so naming #Release here
	// would make #AppRelease unusable in a bundle. The house constraints live in
	// those definitions, and this is the only thing #Bundle reads.
	releases: [...{out: fluxHelm.#HelmRelease, backups: [...{secretFile: string, ...}], ...}]

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

	// SOPS Secret manifests beyond the ones the backups bring in, module-relative.
	// The render step copies them verbatim; ciphertext never passes through CUE.
	// See /workflows/secrets-sops.md.
	extraSecretFiles: [...string] | *[]

	// Deduplicated through a struct, because a workload can hold its restic
	// credential in the same file as its other secrets.
	_secretFileSet: {
		for f in extraSecretFiles {(f): true}
		for r in releases for b in r.backups {(b.secretFile): true}
	}
	secretFiles: [for f, _ in _secretFileSet {f}]

	// Capabilities this bundle needs that its own fields cannot imply, which in
	// practice means the resource is emitted by a chart: CUE sees the HelmRelease,
	// never what it renders. The three below are implied and never written.
	needs: [...#Capability] | *[]

	edges: (_edges & {
		"needs": needs
		// The Middleware set, #NamespaceCert and #VolsyncRestic respectively: each
		// renders a CR another bundle installs the CRD for, so the field that
		// switches it on is the edge.
		inferred: {
			if middlewares {traefik: true}
			if namespaceCert {"cert-manager": true}
			for r in releases if len(r.backups) > 0 {volsync: true}
		}
	}).out

	// Gate the bundle's own resources on readiness rather than on their apply.
	// For a bundle whose content is a HelmRelease this is the gate a consumer
	// wants: Flux assesses the HelmRelease, and helm-controller has already
	// waited for the chart's resources. Only providers set it — a gate on a leaf
	// helps nobody. Flux ignores healthChecks when this is set, which is why the
	// fleet carries no healthChecks at all.
	wait: bool | *false

	// Ceiling on the assessment above.
	timeout:         string | *_defaultTimeout
	_defaultTimeout: string
	if wait {_defaultTimeout: "15m"}
	if !wait {_defaultTimeout: "5m"}

	// Pod Security admission levels and the like. Eight namespaces in the fleet
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
// No namespace of its own, no chart and no releases.
#ConfigBundle: {
	resources: [...]

	// SOPS Secret manifests, module-relative, on the same terms as #Bundle's.
	secretFiles: [...string] | *[]

	// As #Bundle's, with nothing to infer from: a config bundle has no releases,
	// no middleware set and no namespace certificate.
	needs: [...#Capability] | *[]

	edges: (_edges & {"needs": needs, inferred: {}}).out

	// As #Bundle's. certs-config is the only config bundle that gates: its CA
	// chain, issuers and wildcard all carry a real Ready condition, so waiting
	// on the whole inventory is both stronger and simpler than naming two of
	// them.
	wait: bool | *false

	timeout:         string | *_defaultTimeout
	_defaultTimeout: string
	if wait {_defaultTimeout: "15m"}
	if !wait {_defaultTimeout: "5m"}

	out: resources
}

// A tier: one CUE package, one render, one OCI artifact. Collects the bundles
// its workload packages export.
#Tier: {
	// The tier's own identity: where its artifact renders, and the name its
	// OCIRepository and level-2 Kustomization carry.
	tree: "apps" | "infrastructure"
	name: string

	// Constrained by what this definition reads rather than by #Bundle, which is
	// closed and would reject a #ConfigBundle outright.
	bundles: [string]: {
		out: [...]
		secretFiles: [...string]
		edges: [...string]
		wait:    bool
		timeout: string
		...
	}

	rendered: {
		for k, b in bundles {(k): yaml.MarshalStream(b.out)}
	}

	// The SOPS files the render copies verbatim beside the generated manifests.
	// Ciphertext never passes through CUE evaluation; these are paths.
	secretFiles: {
		for k, b in bundles {(k): b.secretFiles}
	}

	// The level-3 Kustomizations, one per bundle, which retire <tier>-sync.yaml
	// and the common-sync-patch component together: interval, timeout, prune,
	// sourceRef and decryption were that patch's entire content.
	//
	// They render into sync/ rather than the artifact root because
	// kustomize-controller's generated kustomization walks subdirectories. At the
	// root, the level-2 Kustomization would apply every workload a second time —
	// and without decryption, which would push SOPS ciphertext into the cluster.
	sync: [for k, b in bundles {
		fluxKustomize.#Kustomization
		apiVersion: "kustomize.toolkit.fluxcd.io/v1"
		kind:       "Kustomization"
		metadata: {"name": k, namespace: "flux-system"}
		spec: {
			interval: "10m"
			// A blocked reconcile otherwise retries at interval, and the graph is
			// six levels deep: at 10m a cold bootstrap would spend an hour waiting
			// rather than working.
			retryInterval: "1m"
			timeout:       b.timeout
			prune:         true
			// source-root relative, not relative to the level-2 path above it
			path: "./\(k)"
			sourceRef: {kind: "OCIRepository", "name": name, namespace: "flux-system"}
			decryption: {provider: "sops", secretRef: "name": "sops-age"}
			// A bundle does not know its own name — bundles is keyed by it — so a
			// provider that needs its own capability is filtered here rather than
			// special-cased in the bundle.
			_deps: [for d in b.edges if d != k {d}]
			if len(_deps) > 0 {
				dependsOn: [for d in _deps {"name": d}]
			}
			if b.wait {wait: true}
		}
	}]
}
