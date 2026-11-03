// Mutation tests on the schema. `cue vet ./...` proves the tree conforms to the
// constraints; it cannot tell a constraint that holds from one that is no longer
// reached. These probe the constraints themselves, and are ordinary CUE so the
// same command covers both.
//
// cSpell:ignore chartt

package probe

import "github.com/joker9944/k8s-config/schema"

// The verdict on a probe: `false` when it evaluates to bottom.
//
// The whole struct has to be the disjunct. Selecting the marker inside it —
// `*(probe & {_ok: true})._ok | false` — reports `true` for a closedness
// violation, because selecting a valid subfield out of an invalid struct
// succeeds. Nor can the probe be bound to a regular field on the way in: a field
// holding bottom is an error whatever the disjunction does with it afterwards.
#Verdict: {
	probe: _
	_r: *(probe & {_ok: true}) | {_ok: false}

	accepted: _r._ok
}

// A minimal valid release for the probes to mutate. Nothing else in the module
// reads it, so a probe stays readable as the one field it changes. The host is
// not part of it, because the two ingress paths disagree on what a valid one
// looks like and a probe cannot mutate a field the fixture already pinned.
_release: schema.#AppRelease & {
	name:      "probe"
	namespace: "probe"

	values: controllers: probe: containers: probe: schema.#Hardened & {
		image: {
			repository: "example.com/probe"
			tag:        "1.0.0@sha256:0000000000000000000000000000000000000000000000000000000000000000"
		}
	}
}

// Behind Traefik, on a public host.
_base: _release & {host: "probe.example.com"}

// Served from the tailnet. The host has to be in the tailnet domain.
_tailnetBase: _release & {
	tailnet: true
	host:    "probe.\(schema.#TailnetDomain)"
}

// A check that stops holding is a unification conflict, so `cue vet ./...`
// reports it by name.
mustReject: [_]: false
mustAccept: [_]: true

mustAccept: {
	// The fixture itself, which is what fails first if _base rots. It also
	// covers the hidden marker staying exempt from closedness.
	"baseline is valid": (#Verdict & {probe: _base}).accepted

	// The generated Flux definitions still admit the API. Without these, a
	// regenerated cue.mod/gen that narrowed every field would leave the
	// rejections below passing for the wrong reason.
	"spec.timeout": (#Verdict & {probe: _base & {out: spec: timeout: "5m"}}).accepted
	"spec.install.crds": (#Verdict & {probe: _base & {out: spec: install: crds: "CreateReplace"}}).accepted
	"spec.driftDetection.mode": (#Verdict & {probe: _base & {out: spec: driftDetection: mode: "enabled"}}).accepted

	// The tailnet path, which replaces the middleware annotations with the
	// operator's class and proxy-group annotation.
	"a tailnet release": (#Verdict & {probe: _tailnetBase}).accepted
}

mustReject: {
	"image without a digest": (#Verdict & {probe: _base & {
		values: controllers: probe: containers: probe: image: tag: "1.0.0"
	}}).accepted

	"readOnlyRootFilesystem disabled": (#Verdict & {probe: _base & {
		values: controllers: probe: containers: probe: securityContext: readOnlyRootFilesystem: false
	}}).accepted

	"middleware from another namespace": (#Verdict & {probe: _base & {
		values: ingress: probe: annotations: "traefik.ingress.kubernetes.io/router.middlewares": "komga_chain-country-whitelist@kubernetescrd"
	}}).accepted

	"middleware chain that does not exist": (#Verdict & {probe: _base & {
		chain: "chain-does-not-exist"
	}}).accepted

	// Undeclared fields: rejected because #Release is closed, not because the
	// schema knows what they mean.
	"a bare middleware in place of a chain": (#Verdict & {probe: _base & {
		bareMiddleware: "network-internal-whitelist"
	}}).accepted

	// A tailnet ingress is not behind Traefik, so the middleware fields are
	// sentinels there rather than defaults.
	"a chain on a tailnet ingress": (#Verdict & {probe: _tailnetBase & {
		chain: "chain-basic"
	}}).accepted

	// The label the operator cuts from the host has to be in the tailnet domain,
	// which is what makes a forgotten host a build error rather than an Ingress
	// advertising a name nobody can reach.
	"a tailnet release on a public host": (#Verdict & {probe: _release & {
		tailnet: true
		host:    "probe.vonarx.online"
	}}).accepted

	"a release taking its values from a Secret": (#Verdict & {probe: _base & {
		secretValuesName: "probe-secret-values"
	}}).accepted

	"field the HelmRelease API does not have": (#Verdict & {probe: _base & {
		out: spec: chartt: {}
	}}).accepted
}
