#!/usr/bin/env bash
# Tier 2: the starting state is the VMs' prereqs snapshot itself, so setup only
# checks that you are on it and that no cluster has been created yet.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_snapshot "$LAB_SNAPSHOT"
[[ "$(hostname)" == cp1 ]] || die "run this lab on cp1 (envs/vagrant/kbook-vm ssh)"
if sudo test -e /etc/kubernetes/admin.conf; then
  die "a cluster already exists on cp1. To start over, restore the snapshot on the host: envs/vagrant/kbook-vm restore ${LAB_SNAPSHOT}"
fi
for node in node1 node2; do
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$node" true || die "cannot ssh to ${node} from cp1"
done
info "Lab ready: containerd and kubeadm ${K8S_VERSION} are installed on cp1, node1, and node2; no cluster exists yet."
