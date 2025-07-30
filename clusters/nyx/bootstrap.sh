#!/bin/bash

set -e

kubectl taint node \
  nyx-worker-1 \
  vonarx.online/weak-node=true:PreferNoSchedule

kubectl create namespace flux-system || true

echo "Enter age secret key"

kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/dev/stdin

flux bootstrap github \
  --owner=joker9944 \
  --repository=k8s-config \
  --branch=cluster-migration \
  --path=clusters/nyx/flux \
  --personal
