#!/usr/bin/env bash
# Checks that the house-style constraints reject what they should, and that the
# generated Flux definitions still admit the real API. Fidelity against
# apps/base/ is gate.sh's job, not this one's.
#
# cue comes from the dev shell, so the constraints are checked with the same
# version render.nix builds with.

# cSpell:ignore chartt

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v cue >/dev/null || {
	echo "cue is not on PATH; run inside the dev shell (direnv, or 'nix develop')" >&2
	exit 1
}

rc=0

check() {
	local mode="$1" desc="$2" body="$3" dir="$work/check"
	rm -rf "$dir"
	cp -r "$here" "$dir"
	rm -f "$dir/verify.sh" "$dir/generate.sh" "$dir/gate.sh" "$dir/gate.py"
	# the probe joins the package that owns the release it constrains
	printf 'package jellyfin\n\n%s\n' "$body" >"$dir/apps/media/jellyfin/check.cue"
	if (cd "$dir" && cue vet -c=false ./...) >"$work/err.txt" 2>&1; then
		[ "$mode" = allow ] && {
			echo "    accepted  $desc"
			return 0
		}
		echo "    ACCEPTED  $desc  <-- constraint is not holding"
		return 1
	fi
	[ "$mode" = reject ] && {
		echo "    rejected  $desc"
		return 0
	}
	echo "    REJECTED  $desc  <-- generated definitions may be stale"
	return 1
}

echo "==> constraint checks (each must be rejected)"
check reject "image without a digest" \
	'_jellyfin: values: controllers: jellyfin: containers: jellyfin: image: tag: "10.11.11"' || rc=1
check reject "readOnlyRootFilesystem disabled" \
	'_jellyfin: values: controllers: jellyfin: containers: jellyfin: securityContext: readOnlyRootFilesystem: false' || rc=1
check reject "middleware from another namespace" \
	'_jellyfin: values: ingress: jellyfin: annotations: "traefik.ingress.kubernetes.io/router.middlewares": "komga-chain-country-whitelist@kubernetescrd"' || rc=1
check reject "middleware chain that does not exist" \
	'_jellyfin: chain: "chain-does-not-exist"' || rc=1
check reject "field the HelmRelease API does not have" \
	'_jellyfin: out: spec: chartt: {}' || rc=1

echo "==> Flux API surface (each must be accepted)"
check allow "spec.timeout" '_jellyfin: out: spec: timeout: "5m"' || rc=1
check allow "spec.install.crds" '_jellyfin: out: spec: install: crds: "CreateReplace"' || rc=1
check allow "spec.driftDetection.mode" '_jellyfin: out: spec: driftDetection: mode: "enabled"' || rc=1

exit "$rc"
