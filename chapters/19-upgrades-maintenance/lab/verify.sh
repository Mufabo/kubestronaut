#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_snapshot "$LAB_SNAPSHOT"
require_lab_cluster

want="${K8S_VERSION#v}-"   # Debian package versions look like 1.35.0-1.1

# Runs a command string on a node: locally on cp1, over SSH on the workers.
on() { if [[ "$1" == cp1 ]]; then bash -c "$2"; else ssh -o BatchMode=yes "$1" "$2"; fi; }

# kubeadm, kubelet, and kubectl on the node are at K8S_VERSION, and all three are held again.
packages_upgraded() {
  local node=$1 versions held p
  # \${Package} and \${Version} are dpkg-query's format, kept literal for the remote shell
  versions="$(on "$node" "dpkg-query -W -f='\${Package} \${Version}\n' kubeadm kubelet kubectl")" &&
  held="$(on "$node" 'apt-mark showhold')" || return 1
  for p in kubeadm kubelet kubectl; do
    grep -q "^${p} ${want}" <<<"$versions" || return 1
    grep -qx "$p" <<<"$held" || return 1
  done
}

kubelet_version() { kubectl get node "$1" -o jsonpath='{.status.nodeInfo.kubeletVersion}'; }
unschedulable() { [[ "$(kubectl get node "$1" -o jsonpath='{.spec.unschedulable}')" == true ]]; }

# Task 1: the control plane runs K8S_VERSION
t1() {
  local cfg images
  cfg="$(kubectl -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}')" &&
  grep -q "kubernetesVersion: ${K8S_VERSION}" <<<"$cfg" &&
  images="$(kubectl -n kube-system get pods -l 'component in (kube-apiserver,kube-controller-manager,kube-scheduler)' \
    -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}')" &&
  [[ "$(grep -c ":${K8S_VERSION}$" <<<"$images")" == 3 ]]
}

# Task 2: cp1's kubelet and kubectl are upgraded, and cp1 is back in service
t2() {
  packages_upgraded cp1 &&
  [[ "$(kubelet_version cp1)" == "$K8S_VERSION" ]] &&
  ! unschedulable cp1
}

# Task 3: node1 is upgraded and back in service
t3() {
  packages_upgraded node1 &&
  [[ "$(kubelet_version node1)" == "$K8S_VERSION" ]] &&
  ! unschedulable node1
}

# Task 4: node2 is upgraded
t4() {
  packages_upgraded node2 &&
  [[ "$(kubelet_version node2)" == "$K8S_VERSION" ]]
}

# Task 5: node2 is cordoned and runs only DaemonSet Pods; web stayed available and its PDB is the original one
t5() {
  local owners uid
  unschedulable node2 &&
  owners="$(kubectl get pods -A --field-selector spec.nodeName=node2 \
    -o jsonpath='{range .items[*]}{.metadata.ownerReferences[0].kind}{"\n"}{end}')" &&
  ! grep -qvx -e DaemonSet -e '' <<<"$owners" &&
  [[ "$(kubectl -n "$LAB_NS" get deployment web -o jsonpath='{.status.availableReplicas}')" == 2 ]] &&
  uid="$(kubectl -n "$LAB_NS" get pdb web -o jsonpath='{.metadata.uid} {.spec.minAvailable}')" &&
  [[ "$uid" == "$(cat "${here}/.state/pdb-uid" 2>/dev/null) 1" ]]
}

check 1 "the control plane (kubeadm-config, API server, controller manager, scheduler) runs ${K8S_VERSION}" \
  "on cp1: switch the apt repository to the new minor version, upgrade the kubeadm package, then kubeadm upgrade apply" t1
check 2 "cp1's kubeadm, kubelet, and kubectl packages are at ${K8S_VERSION} and held; cp1 reports ${K8S_VERSION} and is schedulable" \
  "drain cp1, upgrade the kubelet and kubectl packages, restart the kubelet, uncordon cp1" t2
check 3 "node1's packages are at ${K8S_VERSION} and held; node1 reports ${K8S_VERSION} and is schedulable" \
  "drain node1 from cp1, then on node1: kubeadm package, kubeadm upgrade node, kubelet and kubectl packages, restart the kubelet; uncordon" t3
check 4 "node2's packages are at ${K8S_VERSION} and held; node2 reports ${K8S_VERSION}" \
  "the same steps as node1, on node2" t4
check 5 "node2 is cordoned and runs only DaemonSet Pods; web has 2 available replicas and its original PodDisruptionBudget" \
  "kubectl drain node2 --ignore-daemonsets, and do not uncordon it; never delete the PodDisruptionBudget to get a drain through" t5

finish_checks
