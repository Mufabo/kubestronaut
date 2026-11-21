#!/usr/bin/env bash
# Reference solution for the Chapter 50 lab.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

# Task 1: what Kubernetes itself allocates.
docker exec kbook-control-plane cat /etc/kubernetes/manifests/kube-controller-manager.yaml |
  sed -n 's/.*--cluster-cidr=\([^ ]*\).*/\1/p' | head -n1 > "${LAB_ANSWERS}/cluster-cidr"
podcidr="$(kubectl get node kbook-worker -o jsonpath='{.spec.podCIDR}')"
echo "$((1 << (32 - ${podcidr#*/})))" > "${LAB_ANSWERS}/node-addresses"

# Task 2: the pool the namespace asks for; the waiting Pods retry and get addresses.
# Task 3: a second range for the exhausted pool.
kubectl apply -f - >/dev/null <<YAML
apiVersion: cilium.io/v2alpha1
kind: CiliumPodIPPool
metadata:
  name: blue
spec:
  ipv4:
    cidrs: ["10.20.0.0/16"]
    maskSize: 28
---
apiVersion: cilium.io/v2alpha1
kind: CiliumPodIPPool
metadata:
  name: small
spec:
  ipv4:
    cidrs: ["10.30.0.0/27", "10.30.1.0/26"]
    maskSize: 28
YAML

# Task 4: one Pod on pool blue, chosen by annotation.
kubectl -n "$LAB_NS" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: metrics
  labels: {app: metrics}
  annotations: {ipam.cilium.io/ip-pool: blue}
spec:
  terminationGracePeriodSeconds: 0
  containers:
    - name: metrics
      image: ${AGNHOST_IMAGE}
      args: ["netexec", "--http-port=8080"]
YAML

kubectl -n ch50-blue rollout status deployment/api --timeout=300s >/dev/null
kubectl -n ch50-batch rollout status deployment/batch --timeout=600s >/dev/null
kubectl -n "$LAB_NS" wait --for=condition=Ready pod/metrics --timeout=300s >/dev/null
