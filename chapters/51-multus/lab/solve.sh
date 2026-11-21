#!/usr/bin/env bash
# Reference solution for the Chapter 51 lab.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_lab_cluster
require_cmd helm

# Task 1: stop Cilium from moving other configurations aside, then let Multus
# write its file again.
helm upgrade cilium cilium --repo https://helm.cilium.io --version "$CILIUM_VERSION" \
  --namespace kube-system --reuse-values --set cni.exclusive=false >/dev/null
kubectl -n kube-system rollout restart daemonset/cilium >/dev/null
kubectl -n kube-system rollout status daemonset/cilium --timeout=300s >/dev/null
kubectl -n kube-system rollout restart daemonset/kube-multus-ds >/dev/null
kubectl -n kube-system rollout status daemonset/kube-multus-ds --timeout=300s >/dev/null
multus_first() {
  local n
  for n in $(kind_nodes); do [[ "$(first_cni_conf "$n")" == 00-multus.conf ]] || return 1; done
}
wait_for "Multus's configuration on every node" 120 multus_first

# Task 2: the secondary network.
kubectl -n "$LAB_NS" apply -f - >/dev/null <<'YAML'
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: storage
spec:
  config: |
    {
      "cniVersion": "1.0.0",
      "type": "macvlan",
      "master": "eth0",
      "mode": "bridge",
      "capabilities": {"ips": true},
      "ipam": {"type": "static"}
    }
YAML

# Tasks 3 and 4: Pods attached to it (recreated, since networks attach at start).
pod() { # pod <name> <node> <network-selection-json>
  kubectl -n "$LAB_NS" delete pod "$1" --ignore-not-found --wait=true >/dev/null
  kubectl -n "$LAB_NS" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $1
  annotations:
    k8s.v1.cni.cncf.io/networks: '$3'
spec:
  nodeSelector: {kubernetes.io/hostname: $2}
  terminationGracePeriodSeconds: 0
  containers:
    - name: $1
      image: ${NETSHOOT_IMAGE}
      command: ["sleep", "infinity"]
YAML
}
pod db kbook-worker '[{"name": "storage", "ips": ["172.18.100.21/24"]}]'
pod app kbook-worker2 '[{"name": "storage", "ips": ["172.18.100.22/24"]}]'
pod backup kbook-worker2 '[{"name": "storage", "ips": ["172.18.100.23/24"], "interface": "stor0"}]'
kubectl -n "$LAB_NS" wait --for=condition=Ready pod/db pod/app pod/backup --timeout=300s >/dev/null
