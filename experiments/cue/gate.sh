#!/usr/bin/env bash
# Fidelity gate for the kustomize -> CUE migration. Thin wrapper: everything
# real is in gate.py. Tools come unpinned from the nixpkgs registry, as in
# verify.sh — this is migration scaffolding and dies with apps/base/.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec nix shell nixpkgs#cue nixpkgs#kustomize nixpkgs#yq-go nixpkgs#sops nixpkgs#python3 \
	--command python3 "$here/gate.py" "$@"
