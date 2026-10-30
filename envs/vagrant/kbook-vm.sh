#!/usr/bin/env bash
# Build, start, and restore the Tier 2 VMs (Linux and macOS hosts). kbook-vm.ps1
# is the same driver for Windows. Run it on the host, not inside a VM.
#
#   kbook-vm.sh build                   build all VMs and snapshots (about 30-45 min)
#   kbook-vm.sh restore <snapshot>      prereqs | cluster | cluster-prev
#   kbook-vm.sh snapshots               list the snapshots
#   kbook-vm.sh up | halt | status      start, stop, or show the VMs
#   kbook-vm.sh ssh [vm]                open a shell on a VM (default cp1)
#   kbook-vm.sh destroy                 delete the VMs and their snapshots
#
# Snapshots:
#   prereqs        containerd and kubeadm/kubelet/kubectl at K8S_VERSION, no cluster (Chapter 18)
#   cluster        a ready three-node cluster at K8S_VERSION (most Tier 2 labs)
#   cluster-prev   a ready three-node cluster at K8S_PREV_VERSION (Chapter 19 upgrades it)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"
# shellcheck source=/dev/null
source "${here}/../../versions.env"

SNAPSHOTS="prereqs cluster cluster-prev"
step() { printf '\n\033[36m==> %s  [%s]\033[0m\n' "$1" "$(date +%H:%M:%S)"; }
wait_cluster() {
  vagrant ssh cp1 -c "kubectl wait --for=condition=Ready node --all --timeout=600s >/dev/null && kubectl get nodes -o wide"
}

# build_cluster <k8s-version> <snapshot> <save-prereqs: yes|no>
build_cluster() {
  export KBOOK_K8S_VERSION=$1
  step "Installing kubeadm, kubelet and kubectl $1"
  vagrant provision --provision-with k8s-tools
  if [[ "$3" == yes ]]; then
    KBOOK_SNAPSHOT=prereqs vagrant provision --provision-with mark
    step "Saving snapshot prereqs"
    vagrant snapshot save --force prereqs
  fi
  step "kubeadm init on cp1 ($1)"
  vagrant provision cp1 --provision-with cluster-init
  step "Joining the workers"
  vagrant provision node1 node2 --provision-with cluster-join
  step "Waiting until the Pod network works on every node"
  vagrant provision cp1 --provision-with network-ready
  wait_cluster
  KBOOK_SNAPSHOT=$2 vagrant provision --provision-with mark
  step "Saving snapshot $2"
  vagrant snapshot save --force "$2"
}

case "${1:-help}" in
  build)
    started=$SECONDS
    step "Removing any old VMs";                       vagrant destroy -f
    step "Creating the VMs (no provisioning yet)";     vagrant up --no-provision
    step "Preparing the operating system on every VM"; vagrant provision --provision-with os
    step "Saving the base snapshot os";                vagrant snapshot save --force os
    build_cluster "$K8S_VERSION" cluster yes
    step "Back to the base snapshot for the previous-version cluster"
    vagrant snapshot restore os --no-provision
    build_cluster "$K8S_PREV_VERSION" cluster-prev no
    step "Restoring snapshot cluster"
    vagrant snapshot restore cluster --no-provision
    wait_cluster
    step "Build finished in $(((SECONDS - started) / 60)) minutes. The VMs are on snapshot cluster."
    ;;
  restore)
    name="${2:-}"
    [[ " $SNAPSHOTS " == *" $name "* ]] || { echo "usage: $0 restore <${SNAPSHOTS// /|}>" >&2; exit 2; }
    started=$SECONDS
    step "Restoring snapshot $name on every VM"
    vagrant snapshot restore "$name" --no-provision
    [[ "$name" == prereqs ]] || wait_cluster
    step "Snapshot $name restored in $((SECONDS - started)) seconds. Work on cp1: $0 ssh"
    ;;
  snapshots) vagrant snapshot list ;;
  up)        vagrant up --no-provision ;;
  halt)      vagrant halt ;;
  status)    vagrant status ;;
  ssh)       vagrant ssh "${2:-cp1}" ;;
  destroy)   vagrant destroy -f ;;
  *)         sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
