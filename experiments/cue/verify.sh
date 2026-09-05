#!/usr/bin/env bash
# Renders each ported app two ways and proves they agree, then checks that the
# house-style constraints reject what they should and admit the real Flux API.
#
# Tools are pulled unpinned from the nixpkgs registry: this is an experiment,
# not part of the build. If CUE is adopted, cue moves into flake.nix envParts.

# cSpell:ignore chartt

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

tools=(nixpkgs#cue nixpkgs#kustomize nixpkgs#yq-go)
run() { nix shell "${tools[@]}" --command "$@"; }

rc=0

# Document order is not meaningful to Flux, so both sides are sorted by
# kind/name and their keys sorted before comparison.
normalize() {
	local drop_secrets="$2"
	local filter='[.] | map(select(.kind != null))'
	[ "$drop_secrets" = yes ] && filter="$filter | map(select(.kind != \"Secret\"))"
	run yq ea -o=yaml "$filter | sort_by(.kind + \"/\" + .metadata.name) | sort_keys(..)" "$1"
}

compare() {
	local label="$1" path="$2" expr="$3" drop_secrets="$4" expected="$5"
	shift 5
	echo "==> $label"
	run kustomize build "$root/$path" >"$work/golden.yaml"
	(cd "$here" && run cue export -e "$expr" --out text "$@" ./...) >"$work/rendered.yaml"

	normalize "$work/golden.yaml" "$drop_secrets" >"$work/a.yaml"
	normalize "$work/rendered.yaml" "$drop_secrets" >"$work/b.yaml"

	local total
	total="$(wc -l <"$work/a.yaml")"
	local differing=0
	diff -u "$work/a.yaml" "$work/b.yaml" >"$work/diff.txt" ||
		differing="$(grep -cE '^[+-][^+-]' "$work/diff.txt")"

	local note=""
	[ "$drop_secrets" = yes ] && note=" (Secrets excluded)"

	if [ "$differing" -eq 0 ]; then
		echo "    identical across $total lines$note"
	elif [ "$differing" -eq "$expected" ]; then
		# the documented secretGenerator hash deviation; see README
		echo "    $differing of $total lines differ, as expected$note:"
		grep -E '^[+-][^+-]' "$work/diff.txt" | sed 's/^/      /'
	else
		echo "    $differing of $total lines differ, expected $expected$note:"
		grep -E '^[+-][^+-]' "$work/diff.txt" | sed 's/^/      /'
		rc=1
	fi
}

# jellyfin: one release, its SOPS values Secret injected and compared
secret="$(run yq -r 'select(.kind=="Secret") | .data."values.yaml"' \
	<(run kustomize build "$root/apps/base/jellyfin"))"$'\n'
compare "jellyfin" "apps/base/jellyfin" "manifests" no 4 -t secretdata="$secret"

# servarr: six releases in one namespace on a shared Postgres cluster.
# Its 15 SOPS Secrets are pure passthrough (proven above) and are not modelled.
recyclarr_files="$root/apps/base/servarr/recyclarr/files"
compare "servarr" "apps/base/servarr" "servarrManifests" yes 0 \
	-t recyclarrConfig="$(cat "$recyclarr_files/recyclarr.yml")"$'\n' \
	-t recyclarrSettings="$(cat "$recyclarr_files/settings.yml")"$'\n'

echo "==> constraint checks (each must be rejected)"
check() {
	local mode="$1" desc="$2" body="$3" dir="$work/check"
	rm -rf "$dir"
	cp -r "$here" "$dir"
	rm -f "$dir/verify.sh" "$dir/generate.sh"
	printf 'package nyx\n\n%s\n' "$body" >"$dir/check.cue"
	if (cd "$dir" && run cue vet -c=false ./...) >"$work/err.txt" 2>&1; then
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
