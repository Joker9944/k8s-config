#!/usr/bin/env bash
# Regenerates cue.mod/gen from Flux's own Go API packages.
#
# Versions are read from clusters/nyx/flux/flux-system/gotk-components.yaml, so
# the definitions always track the controllers actually running on nyx. Rerun
# after a Flux upgrade; the resulting diff is the API change, made reviewable.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"
components="$root/clusters/nyx/flux/flux-system/gotk-components.yaml"
work="$(mktemp -d)"
# the Go module cache is written read-only; make it removable first
trap 'chmod -R u+w "$work" 2>/dev/null || true; rm -rf "$work"' EXIT

tools=(nixpkgs#go nixpkgs#cue)
run() { nix shell "${tools[@]}" --command "$@"; }

version_of() {
	grep -oE "ghcr\.io/fluxcd/$1:v[0-9.]+" "$components" | head -1 | sed 's/.*://'
}

declare -A pkgs=(
	[helm - controller]=api/v2
	[kustomize - controller]=api/v1
	[source - controller]=api/v1
)

mkdir -p "$work/cue.mod"
cp "$here/cue.mod/module.cue" "$work/cue.mod/module.cue"

cd "$work"
export GOPATH="$work/go" GOMODCACHE="$work/go/pkg/mod" GOCACHE="$work/go-cache"
export GOFLAGS=-mod=mod
# go/packages type-checks the stdlib; without a C toolchain cgo files fail to load
export CGO_ENABLED=0

run go mod init example.com/flux-gen >/dev/null

# Fetch everything before converting anything: cue get go type-checks the whole
# dependency graph, so a partially-populated go.mod fails on embedded types.
for ctrl in "${!pkgs[@]}"; do
	v="$(version_of "$ctrl")"
	echo "==> fetching $ctrl $v"
	run go get "github.com/fluxcd/$ctrl/api@$v"
done

for ctrl in "${!pkgs[@]}"; do
	echo "==> converting $ctrl/${pkgs[$ctrl]}"
	run cue get go "github.com/fluxcd/$ctrl/${pkgs[$ctrl]}"
done

rm -rf "$here/cue.mod/gen"
cp -r "$work/cue.mod/gen" "$here/cue.mod/gen"
echo "==> wrote $(find "$here/cue.mod/gen" -name '*.cue' | wc -l) files to cue.mod/gen"
