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
// reads it, so a probe stays readable as the one field it changes.
_base: schema.#AppRelease & {
	name:      "probe"
	namespace: "probe"
	host:      "probe.example.com"

	values: controllers: probe: containers: probe: schema.#Hardened & {
		image: {
			repository: "example.com/probe"
			tag:        "1.0.0@sha256:0000000000000000000000000000000000000000000000000000000000000000"
		}
	}
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

	"a release taking its values from a Secret": (#Verdict & {probe: _base & {
		secretValuesName: "probe-secret-values"
	}}).accepted

	"field the HelmRelease API does not have": (#Verdict & {probe: _base & {
		out: spec: chartt: {}
	}}).accepted
}
