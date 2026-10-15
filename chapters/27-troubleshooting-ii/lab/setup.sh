#!/usr/bin/env bash
# Tier 2: starts from the cluster snapshot and breaks it in three places:
# node1's kubelet, node2's kubelet configuration, and the scheduler. The
# certificate tasks start from the cluster as it is.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

require_snapshot "$LAB_SNAPSHOT"
[[ "$(hostname)" == cp1 ]] || die "run this lab on cp1 (envs/vagrant/kbook-vm ssh)"
require_lab_cluster
for node in node1 node2; do
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$node" true || die "cannot ssh to ${node} from cp1"
done

rm -f "$CA_EXPIRY_FILE"
mkdir -p "${here}/.state"
# Task 5 must renew the API server certificate: remember the one in place now.
cert_not_after /etc/kubernetes/pki/apiserver.crt > "${here}/.state/apiserver-not-after"
[[ -s "${here}/.state/apiserver-not-after" ]] || die "cannot read /etc/kubernetes/pki/apiserver.crt"

lab_teardown_ns "$LAB_NS"
lab_create_ns "$LAB_NS"

# Fault 1: node1's kubelet is stopped, and will not start at boot either.
ssh -o BatchMode=yes node1 'sudo systemctl disable --now kubelet' >/dev/null 2>&1

# Fault 2: node2's kubelet talks to the wrong port of the API server.
ssh -o BatchMode=yes node2 "sudo sed -i 's|server: https://${CP_IP}:6443|server: https://${CP_IP}:6444|' /etc/kubernetes/kubelet.conf && sudo systemctl restart kubelet"

# Fault 3: the scheduler's manifest names a kubeconfig file that does not exist.
sudo sed -i 's|--kubeconfig=/etc/kubernetes/scheduler.conf$|--kubeconfig=/etc/kubernetes/scheduler.config|' "$SCHEDULER_MANIFEST"
scheduler_down() { [[ -z "$(crictl_k8s ps --name kube-scheduler -q)" ]]; }
info "Waiting for the faults to show (up to a few minutes)"
wait_for "the scheduler is down" 300 scheduler_down

# Created while nothing can schedule it.
kubectl -n "$LAB_NS" apply -f "${here}/../manifests/web.yaml" >/dev/null

node_not_ready() { ! node_ready "$1"; }
wait_for "node1 NotReady" 300 node_not_ready node1
wait_for "node2 NotReady" 300 node_not_ready node2

info "Lab ready: something is wrong with node1, node2, and the control plane. Namespace: ${LAB_NS}"
