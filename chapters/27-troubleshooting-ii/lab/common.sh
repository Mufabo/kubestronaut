# shellcheck shell=bash
# Shared by setup, verify, and solve. Sourced after lib.sh and lab.env.

crictl_k8s() { sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock "$@" 2>/dev/null; }

node_ready() {
  [[ "$(kubectl get node "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == True ]]
}

# The expiry date (notAfter) of a certificate file, as openssl prints it.
cert_not_after() { sudo openssl x509 -enddate -noout -in "$1" 2>/dev/null | cut -d= -f2; }

# The serial number of the certificate the API server actually serves.
served_apiserver_serial() {
  openssl s_client -connect "${CP_IP}:6443" </dev/null 2>/dev/null | openssl x509 -serial -noout 2>/dev/null | cut -d= -f2
}
