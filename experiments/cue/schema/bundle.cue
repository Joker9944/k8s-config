package schema

import (
	"encoding/yaml"
	"list"
	"strings"
	fluxHelm "github.com/fluxcd/helm-controller/api/v2"
	fluxSource "github.com/fluxcd/source-controller/api/v1"
)

// One HelmRelease from the bjw-s app-template chart. Typed against
// helm-controller's own Go API, so the whole Flux surface is available and
// anything outside it is a build error.
#Release: {
	name:      string
	namespace: string
	version:   string | *"4.6.2"

	// Ingress wiring. The middleware reference is computed, never written by
	// the caller, so a release cannot name another namespace's middleware.
	host:       string | *"" // "" means no ingress
	ingressKey: string | *name
	chain:      #Chain | *"chain-country-whitelist"
	extraMiddlewares: [...string] | *[]

	secretValuesName: string | *""
	values: {...}

	_middlewareRef: strings.Join([
		for m in list.Concat([[chain], extraMiddlewares]) {"\(namespace)-\(m)@kubernetescrd"},
	], ",")

	out: fluxHelm.#HelmRelease & {
		apiVersion: "helm.toolkit.fluxcd.io/v2"
		kind:       "HelmRelease"
		metadata: {"name": name, "namespace": namespace}
		spec: {
			interval: "30m"
			chart: spec: {
				chart:     "app-template"
				interval:  "30m"
				"version": version
				sourceRef: {kind: "HelmRepository", name: "bjw-s", "namespace": namespace}
			}
			if secretValuesName != "" {
				valuesFrom: [{kind: "Secret", name: secretValuesName}]
			}
			"values": values & {
				global: alwaysAppendIdentifierToResourceName: true
				if host != "" {
					ingress: (ingressKey): annotations: {
						"traefik.ingress.kubernetes.io/router.tls":         "true"
						"traefik.ingress.kubernetes.io/router.entrypoints": "websecure"
						"traefik.ingress.kubernetes.io/router.middlewares": _middlewareRef
					}
				}
			}
		}
	}
}

// A namespace and everything shared inside it: the HelmRepository and the
// Traefik middleware set, installed once regardless of how many releases live
// there. Replaces manifests/namespace.yaml, kustomization.yaml, and the
// bjw-s-helm-repository / common-middlewares / common-kustomizeconfig components.
#Bundle: {
	namespace: string
	releases: [...#Release]
	before: [...] | *[] // emitted between the namespace and the releases
	after: [...] | *[]  // emitted after the releases

	// SOPS Secret manifests, module-relative. The render step copies them
	// verbatim; ciphertext never passes through CUE. See
	// /workflows/secrets-sops.md.
	secretFiles: [...string] | *[]

	// Migration bookkeeping: the kustomize overlay this bundle replaces, read
	// by gate.py. "" means not yet ported. Goes away with apps/base/.
	source: string | *""

	_ns: {apiVersion: "v1", kind: "Namespace", metadata: name: namespace}

	_repo: fluxSource.#HelmRepository & {
		apiVersion: "source.toolkit.fluxcd.io/v1"
		kind:       "HelmRepository"
		metadata: {name: "bjw-s", "namespace": namespace}
		spec: {interval: "5m", url: "https://bjw-s-labs.github.io/helm-charts"}
	}

	_mw: #Middlewares & {ns: namespace}

	out: list.Concat([
		[_ns],
		before,
		[for r in releases {r.out}],
		after,
		[_repo],
		_mw.out,
	])
}

// A tier: one CUE package, one render, one OCI artifact. Collects the bundles
// its workload packages export.
#Tier: {
	bundles: [string]: #Bundle

	rendered: {
		for k, b in bundles {(k): yaml.MarshalStream(b.out)}
	}

	// The registry gate.py reads, so the script carries no per-app knowledge.
	// Goes away with apps/base/.
	gateMeta: {
		for k, b in bundles {
			(k): {namespace: b.namespace, source: b.source, secretFiles: b.secretFiles}
		}
	}
}
