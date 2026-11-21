#!/usr/bin/env bash
# Chapter 50 lab: a brand-new kind cluster with Cilium in multi-pool IPAM mode
# (default pool 10.10.0.0/16, /27 per node block). Two things are broken:
#   ch50-blue:  the namespace asks for pool "blue", which does not exist, so
#               the Deployment api cannot start.
#   ch50-batch: pool "small" (10.30.0.0/27, /28 blocks) is too small for the
#               40 replicas of the Deployment batch.
# ch50-ipam holds client, a netshoot Pod on the default pool.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_cmd helm

cluster_fresh "$LAB_PROFILE"
lab_course_reset "$LAB_ANSWERS" .

info "installing Cilium ${CILIUM_VERSION} with multi-pool IPAM (a few minutes)"
helm install cilium cilium --repo https://helm.cilium.io --version "$CILIUM_VERSION" \
  --namespace kube-system \
  --set ipam.mode=multi-pool \
  --set 'ipam.operator.autoCreateCiliumPodIPPools.default.ipv4.cidrs={10.10.0.0/16}' \
  --set ipam.operator.autoCreateCiliumPodIPPools.default.ipv4.maskSize=27 \
  --set routingMode=native --set autoDirectNodeRoutes=true --set ipv4NativeRoutingCIDR=10.0.0.0/8 \
  --set egressMasqueradeInterfaces=eth0 >/dev/null
kubectl -n kube-system rollout status daemonset/cilium --timeout=600s >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=300s >/dev/null
wait_for "the CiliumPodIPPool API" 180 kubectl get crd ciliumpodippools.cilium.io

kubectl apply -f - >/dev/null <<YAML
apiVersion: cilium.io/v2alpha1
kind: CiliumPodIPPool
metadata:
  name: small
spec:
  ipv4:
    cidrs: ["10.30.0.0/27"]
    maskSize: 28
YAML

lab_create_ns "$LAB_NS"
lab_create_ns ch50-blue
lab_create_ns ch50-batch
kubectl annotate namespace ch50-blue ipam.cilium.io/ip-pool=blue --overwrite >/dev/null
kubectl annotate namespace ch50-batch ipam.cilium.io/ip-pool=small --overwrite >/dev/null

kubectl apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: ${LAB_NS}
  labels: {app: client}
spec:
  nodeSelector: {kubernetes.io/hostname: kbook-worker}
  terminationGracePeriodSeconds: 0
  containers:
    - name: client
      image: ${NETSHOOT_IMAGE}
      command: ["sleep", "infinity"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: ch50-blue
spec:
  replicas: 3
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      terminationGracePeriodSeconds: 0
      containers:
        - name: api
          image: ${AGNHOST_IMAGE}
          args: ["netexec", "--http-port=8080"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch
  namespace: ch50-batch
spec:
  replicas: 40
  selector: {matchLabels: {app: batch}}
  template:
    metadata: {labels: {app: batch}}
    spec:
      terminationGracePeriodSeconds: 0
      containers:
        - name: batch
          image: ${AGNHOST_IMAGE}
          args: ["pause"]
YAML
wait_for "client to run" 180 pod_phase_is "$LAB_NS" client Running
info "Lab ready: ch50-blue and ch50-batch have Pods that cannot get an address."
