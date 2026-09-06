#!/usr/bin/env bash
# Fidelity gate for the kustomize -> CUE migration. Thin wrapper: everything
# real is in gate.py.
#
# cue comes from the dev shell so it is the same one render.nix builds with; the
# rest are pulled from the registry, since their version cannot change what is
# compared. This is migration scaffolding and dies with apps/base/.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v cue >/dev/null || {
	echo "cue is not on PATH; run inside the dev shell (direnv, or 'nix develop')" >&2
	exit 1
}

exec nix shell nixpkgs#kustomize nixpkgs#yq-go nixpkgs#sops nixpkgs#python3 \
	--command python3 "$here/gate.py" "$@"
