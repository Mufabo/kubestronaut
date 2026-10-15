#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_snapshot "$LAB_SNAPSHOT"
require_lab_cluster

# Task 1: node1 is Ready, and its kubelet runs now and starts at boot
t1() {
  local state
  node_ready node1 &&
  state="$(ssh -o BatchMode=yes node1 'systemctl is-active kubelet; systemctl is-enabled kubelet' 2>/dev/null)" &&
  [[ "$state" == $'active\nenabled' ]]
}

# Task 2: node2 is Ready, and its kubelet's kubeconfig points at the API server's real port
t2() {
  local server
  node_ready node2 &&
  server="$(ssh -o BatchMode=yes node2 "sudo grep 'server:' /etc/kubernetes/kubelet.conf" 2>/dev/null)" &&
  [[ "$(tr -d '[:space:]' <<<"$server")" == "server:https://${CP_IP}:6443" ]]
}

# Task 3: the scheduler runs, and it placed both web Pods (no nodeName set by hand)
t3() {
  local ready nodename avail
  ready="$(kubectl -n kube-system get pod kube-scheduler-cp1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" &&
  [[ "$ready" == True ]] &&
  nodename="$(kubectl -n "$LAB_NS" get deployment web -o jsonpath='{.spec.template.spec.nodeName}')" &&
  [[ -z "$nodename" ]] &&
  avail="$(kubectl -n "$LAB_NS" get deployment web -o jsonpath='{.status.availableReplicas}')" &&
  [[ "$avail" == 2 ]]
}

# Task 4: the expiry date of the cluster CA, as openssl prints it, and nothing else
t4() {
  local want
  want="$(cert_not_after /etc/kubernetes/pki/ca.crt)" && [[ -n "$want" ]] &&
  [[ "$(sed -e 's/^notAfter=//' -e 's/[[:space:]]*$//' "$CA_EXPIRY_FILE" 2>/dev/null)" == "$want" ]]
}

# Task 5: the API server certificate was renewed, and the API server serves the renewed one
t5() {
  local before after file_serial
  before="$(cat "${here}/.state/apiserver-not-after" 2>/dev/null)" && [[ -n "$before" ]] &&
  after="$(cert_not_after /etc/kubernetes/pki/apiserver.crt)" && [[ -n "$after" ]] &&
  (($(date -d "$after" +%s) > $(date -d "$before" +%s))) &&
  file_serial="$(sudo openssl x509 -serial -noout -in /etc/kubernetes/pki/apiserver.crt | cut -d= -f2)" &&
  [[ "$(served_apiserver_serial)" == "$file_serial" ]]
}

check 1 "node1 is Ready; its kubelet is running and enabled at boot" \
  "ssh node1, then systemctl status kubelet and journalctl -u kubelet" t1
check 2 "node2 is Ready; its kubelet's kubeconfig uses https://${CP_IP}:6443" \
  "ssh node2, then journalctl -u kubelet: what does the kubelet fail to connect to?" t2
check 3 "the scheduler runs, and it scheduled both replicas of web in ${LAB_NS}" \
  "kubectl -n kube-system get pods, then the scheduler's logs; its manifest is in /etc/kubernetes/manifests" t3
check 4 "${CA_EXPIRY_FILE} holds the expiry date of /etc/kubernetes/pki/ca.crt, as openssl prints it" \
  "openssl x509 -enddate -noout -in /etc/kubernetes/pki/ca.crt, or kubeadm certs check-expiration" t4
check 5 "/etc/kubernetes/pki/apiserver.crt is renewed, and the API server serves the renewed certificate" \
  "kubeadm certs renew apiserver, then compare the file with what the API server serves (openssl s_client); restart the API server if they differ" t5

finish_checks
