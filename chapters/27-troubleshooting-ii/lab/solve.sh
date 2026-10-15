#!/usr/bin/env bash
# Automated reference solution (used to test the lab on cp1). Human-readable version: solutions.md
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

# Task 1
ssh -o BatchMode=yes node1 'sudo systemctl enable --now kubelet' >/dev/null 2>&1

# Task 2
ssh -o BatchMode=yes node2 "sudo sed -i 's|server: https://${CP_IP}:6444|server: https://${CP_IP}:6443|' /etc/kubernetes/kubelet.conf && sudo systemctl restart kubelet"

# Task 3
sudo sed -i 's|--kubeconfig=/etc/kubernetes/scheduler.config$|--kubeconfig=/etc/kubernetes/scheduler.conf|' "$SCHEDULER_MANIFEST"
wait_for "node1 Ready" 300 node_ready node1
wait_for "node2 Ready" 300 node_ready node2
web_available() { [[ "$(kubectl -n "$LAB_NS" get deployment web -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" == 2 ]]; }
wait_for "web has 2 available replicas" 600 web_available

# Task 4
cert_not_after /etc/kubernetes/pki/ca.crt > "$CA_EXPIRY_FILE"

# Task 5: renew, then make sure the API server serves the renewed certificate.
# It reloads its serving certificate from disk; a restart (moving its manifest
# out and back) is the fallback if it still serves the old one.
sudo kubeadm certs renew apiserver >/dev/null
serves_renewed() {
  [[ "$(served_apiserver_serial)" == "$(sudo openssl x509 -serial -noout -in /etc/kubernetes/pki/apiserver.crt | cut -d= -f2)" ]]
}
# wait_for exits on a timeout, so the first wait runs in a subshell.
if ! (wait_for "the API server serves the renewed certificate" 120 serves_renewed 2>/dev/null); then
  apiserver_stopped() { [[ -z "$(crictl_k8s ps --name kube-apiserver -q)" ]]; }
  sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/kube-apiserver.yaml
  wait_for "the API server stopped" 300 apiserver_stopped
  sudo mv /etc/kubernetes/kube-apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml
  wait_for "the API server serves the renewed certificate" 600 serves_renewed
fi
scheduler_ready() {
  [[ "$(kubectl -n kube-system get pod kube-scheduler-cp1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == True ]]
}
wait_for "the scheduler Ready" 300 scheduler_ready
