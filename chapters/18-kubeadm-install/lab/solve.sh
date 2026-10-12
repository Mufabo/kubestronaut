#!/usr/bin/env bash
# Automated reference solution (used by CI on cp1). Human-readable version: solutions.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_snapshot "$LAB_SNAPSHOT"

# Task 1: on a one-CPU VM, kubeadm's two-CPU check has to be skipped
preflight=()
(($(nproc) < 2)) && preflight=(--ignore-preflight-errors=NumCPU)
sudo kubeadm init --apiserver-advertise-address="$CP_IP" --pod-network-cidr="$POD_CIDR" \
  --kubernetes-version="$K8S_VERSION" "${preflight[@]}" >/dev/null

# Task 2
mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
kubectl config rename-context "$(kubectl config current-context)" "$LAB_CONTEXT" >/dev/null

# Task 3: the manifest's pool defaults to 192.168.0.0/16, which contains the VM network
curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml" |
  sed -e 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' \
      -e "s|#   value: \"192.168.0.0/16\"|  value: \"${POD_CIDR}\"|" |
  kubectl apply -f - >/dev/null
kubectl -n kube-system rollout status daemonset/calico-node --timeout=600s >/dev/null

# Task 4
join="$(sudo kubeadm token create --print-join-command)"
for node in node1 node2; do
  # shellcheck disable=SC2029  # the join command is meant to expand here, on cp1
  ssh "$node" "sudo ${join}" >/dev/null
done
kubectl wait --for=condition=Ready node --all --timeout=600s >/dev/null
kubectl -n kube-system rollout status daemonset/calico-node --timeout=600s >/dev/null
calico_ready_everywhere() {
  [[ "$(kubectl -n kube-system get daemonset calico-node -o jsonpath='{.status.numberReady}')" == 3 ]]
}
wait_for "calico-node ready on all three nodes" 600 calico_ready_everywhere

# Task 5
kubectl label node node1 node2 node-role.kubernetes.io/worker= >/dev/null
