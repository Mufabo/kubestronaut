#!/usr/bin/env bash
# Stage "network-ready", cp1 only: wait until the Pod network really works on
# every node before the driver saves a snapshot. Nodes report Ready as soon as
# the CNI config exists, which is before Calico has finished on a freshly joined
# worker; a snapshot taken then keeps that worker half-configured (its Felix
# waits forever for a tunnel address). Runs as root.
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf

tunnel_addr() { kubectl get node "$1" -o jsonpath='{.metadata.annotations.projectcalico\.org/IPv4IPIPTunnelAddr}'; }

kubectl wait --for=condition=Ready node --all --timeout=600s >/dev/null
kubectl -n kube-system rollout status daemonset/calico-node --timeout=600s >/dev/null

for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  for attempt in 1 2 3; do
    for _ in $(seq 1 24); do
      [[ -n "$(tunnel_addr "$node")" ]] && break
      sleep 5
    done
    [[ -n "$(tunnel_addr "$node")" ]] && break
    echo "calico on ${node} has no tunnel address after 2 minutes; restarting it (attempt ${attempt})"
    kubectl -n kube-system delete pod -l k8s-app=calico-node --field-selector "spec.nodeName=${node}" --wait=true >/dev/null
    kubectl -n kube-system rollout status daemonset/calico-node --timeout=300s >/dev/null
  done
  [[ -n "$(tunnel_addr "$node")" ]] || { echo "calico on ${node} never got a tunnel address" >&2; exit 1; }
done
kubectl -n kube-system rollout status deployment/coredns --timeout=300s >/dev/null

# Prove it: a DNS lookup of the API Service from a Pod on every node.
ns=kbook-network-ready
kubectl delete namespace "$ns" --ignore-not-found --wait=true >/dev/null
kubectl create namespace "$ns" >/dev/null
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  kubectl -n "$ns" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: dns-${node}
spec:
  nodeName: ${node}
  restartPolicy: Never
  tolerations: [{operator: Exists}]
  containers:
    - name: dns
      image: busybox:1.36
      command: ["sh", "-c", "for i in 1 2 3 4 5 6; do nslookup kubernetes.default.svc.cluster.local && exit 0; sleep 5; done; exit 1"]
YAML
done
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  phase=""
  for _ in $(seq 1 60); do
    phase="$(kubectl -n "$ns" get pod "dns-${node}" -o jsonpath='{.status.phase}')"
    [[ "$phase" == Succeeded || "$phase" == Failed ]] && break
    sleep 5
  done
  [[ "$phase" == Succeeded ]] || { echo "cluster DNS does not work from ${node} (phase: ${phase:-none})" >&2; exit 1; }
  echo "cluster DNS works from ${node}"
done
kubectl delete namespace "$ns" --wait=true >/dev/null
