#!/usr/bin/env bash
# Automated reference solution (used to test the lab on cp1). Human-readable version: solutions.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_snapshot "$LAB_SNAPSHOT"
require_lab_cluster

prev_minor="$(cut -d. -f1-2 <<<"$K8S_PREV_VERSION")"   # v1.34
minor="$(cut -d. -f1-2 <<<"$K8S_VERSION")"             # v1.35

on() { if [[ "$1" == cp1 ]]; then bash -c "$2"; else ssh -o BatchMode=yes "$1" "$2"; fi; }

# Points the node's apt source at the new minor version, then installs the given
# packages at exactly K8S_VERSION and holds them again.
upgrade_packages() {
  local node=$1; shift
  local pkgs="$*" args="" p
  for p in "$@"; do args+=" ${p}=\$v"; done
  on "$node" "set -e
    sudo sed -i 's|/${prev_minor}/|/${minor}/|' /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update -qq
    v=\$(apt-cache madison kubeadm | awk '{print \$3}' | grep '^${K8S_VERSION#v}-' | head -1)
    sudo apt-mark unhold ${pkgs} >/dev/null
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o Dpkg::Options::=--force-confold ${args} >/dev/null
    sudo apt-mark hold ${pkgs} >/dev/null"
}
restart_kubelet() { on "$1" 'sudo systemctl daemon-reload && sudo systemctl restart kubelet'; }
# Drain is idempotent, so a drain cut short by an API server restart is retried.
drain_once() { kubectl drain "$1" --ignore-daemonsets --delete-emptydir-data --force --timeout=300s >/dev/null 2>&1; }
uncordon_once() { kubectl uncordon "$1" >/dev/null 2>&1; }
drain() { wait_for "${1} drained" 600 drain_once "$1"; }
# The new kubelet on cp1 restarts the static Pods, so the API server goes away
# for a while after the kubelet itself is back. Stable means: Ready for 30s.
api_stable() {
  local since
  kubectl get --raw /readyz >/dev/null 2>&1 &&
  since="$(kubectl -n kube-system get pod kube-apiserver-cp1 \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)" &&
  [[ -n "$since" ]] && (($(date +%s) - $(date -d "$since" +%s) >= 30))
}
kubelet_at_target() { [[ "$(kubectl get node "$1" -o jsonpath='{.status.nodeInfo.kubeletVersion}')" == "$K8S_VERSION" ]]; }
node_ready() { [[ "$(kubectl get node "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" == True ]]; }

# Task 1: kubeadm first, then the control plane
upgrade_packages cp1 kubeadm
sudo kubeadm upgrade apply -y "$K8S_VERSION" >/dev/null

# Task 2: the kubelet and kubectl on cp1
drain cp1
upgrade_packages cp1 kubelet kubectl
restart_kubelet cp1
wait_for "cp1 reports ${K8S_VERSION}" 300 kubelet_at_target cp1
wait_for "cp1 Ready" 300 node_ready cp1
wait_for "API server stable after the kubelet restart" 600 api_stable
wait_for "cp1 uncordoned" 300 uncordon_once cp1

# Tasks 3 and 4: one worker at a time
for node in node1 node2; do
  drain "$node"
  upgrade_packages "$node" kubeadm
  on "$node" 'sudo kubeadm upgrade node' >/dev/null
  upgrade_packages "$node" kubelet kubectl
  restart_kubelet "$node"
  wait_for "${node} reports ${K8S_VERSION}" 300 kubelet_at_target "$node"
  wait_for "${node} Ready" 300 node_ready "$node"
  # Task 5: node2 stays drained and cordoned
  [[ "$node" == node2 ]] || wait_for "${node} uncordoned" 300 uncordon_once "$node"
done

web_available() { [[ "$(kubectl -n "$LAB_NS" get deployment web -o jsonpath='{.status.availableReplicas}')" == 2 ]]; }
wait_for "web has 2 available replicas" 300 web_available
