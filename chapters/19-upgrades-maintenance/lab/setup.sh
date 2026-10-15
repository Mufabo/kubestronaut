#!/usr/bin/env bash
# Tier 2: the starting state is the cluster-prev snapshot (every node at
# K8S_PREV_VERSION) plus a small workload that a careless drain would break.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_snapshot "$LAB_SNAPSHOT"
[[ "$(hostname)" == cp1 ]] || die "run this lab on cp1 (envs/vagrant/kbook-vm ssh)"
require_lab_cluster
for node in node1 node2; do
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$node" true || die "cannot ssh to ${node} from cp1"
done

# The upgrade cannot be undone in place: if it has started, only a snapshot restore resets the lab.
versions="$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' | sort -u)"
if [[ "$versions" != "$K8S_PREV_VERSION" ]] ||
   [[ "$(kubectl -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}')" != *"kubernetesVersion: ${K8S_PREV_VERSION}"* ]]; then
  die "the cluster is no longer at ${K8S_PREV_VERSION} everywhere. To start over, restore the snapshot on the host: envs/vagrant/kbook-vm restore ${LAB_SNAPSHOT}"
fi

lab_teardown_ns "$LAB_NS"
mkdir -p "${here}/.state"
rm -f "${here}/.state/pdb-uid"
lab_create_ns "$LAB_NS"
kubectl -n "$LAB_NS" apply -f "${here}/../manifests/web.yaml" >/dev/null
# Task 5 must keep the PodDisruptionBudget: remember its identity.
kubectl -n "$LAB_NS" get pdb web -o jsonpath='{.metadata.uid}' > "${here}/.state/pdb-uid"

info "Waiting for the web Deployment and the debug Pod (image pulls may take a moment)"
web_available() { [[ "$(kubectl -n "$LAB_NS" get deployment web -o jsonpath='{.status.availableReplicas}')" == 2 ]]; }
wait_for "web has 2 available replicas" 300 web_available
wait_for "debug Pod Running" 300 pod_phase_is "$LAB_NS" debug Running

info "Lab ready: cp1, node1, and node2 run ${K8S_PREV_VERSION}. Namespace: ${LAB_NS}"
