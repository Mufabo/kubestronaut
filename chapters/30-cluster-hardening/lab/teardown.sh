#!/usr/bin/env bash
# shellcheck disable=SC2029  # variables in ssh commands are meant to expand on cp1
# Remove the lab's Namespace and binaries, and put node1's kubelet back the way
# kubeadm configured it. Profiling settings (Task 2), file permissions on node2,
# and kube-bench stay; restore the snapshot on the host to undo them.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

require_snapshot "$LAB_SNAPSHOT"
require_lab_cluster
lab_teardown_ns "$LAB_NS"
sudo rm -rf "$BIN_DIR"
rm -f "${STATE}/genuine" "${STATE}/genuine.sha512"
ssh node1 "sudo sed -i -e '/^  anonymous:/{n;s/enabled: true/enabled: false/}' -e '/^authorization:/{n;s/mode: AlwaysAllow/mode: Webhook/}' -e '/^readOnlyPort:/d' ${KUBELET_CONFIG} && sudo systemctl restart kubelet"
wait_for "node1 Ready" 180 node_ready node1
lab_restore_kubectx "${STATE}/kubectx"
info "Lab removed. To undo Task 2 and the other changes too, restore the snapshot on the host: envs/vagrant/kbook-vm restore ${LAB_SNAPSHOT}"
