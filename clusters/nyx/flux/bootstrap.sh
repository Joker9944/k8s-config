#!/bin/bash

set -e

kubectl create namespace flux-system || true

kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/dev/stdin

flux bootstrap github \
  --owner=joker9944 \
  --repository=k8s-config \
  --branch=cluster-migration \
  --path=clusters/nyx/flux \
  --personal
