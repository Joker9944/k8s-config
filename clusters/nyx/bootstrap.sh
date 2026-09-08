#!/usr/bin/env bash

set -e

kubectl create namespace flux-system || true

echo "Enter age secret key"

kubectl create secret generic sops-age \
	--namespace=flux-system \
	--from-file=age.agekey=/dev/stdin

GITHUB_TOKEN="$(gh auth token)"
export GITHUB_TOKEN

flux bootstrap github \
	--owner=joker9944 \
	--repository=k8s-config \
	--path=clusters/nyx/flux \
	--version=v2.9.5 \
	--personal
