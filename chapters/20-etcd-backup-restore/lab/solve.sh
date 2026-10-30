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
etcdctl_k8s snapshot save "$NEW_BACKUP" >/dev/null 2>&1

# Task 2
sudo etcdutl snapshot status "$NEW_BACKUP" -w json | sed -nE 's/.*"revision":([0-9]+).*/\1/p' > "$REVISION_FILE"

# Task 3, in the documented order: stop the API server, restore, point etcd at the new data
crictl_k8s() { sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock "$@" 2>/dev/null; }
apiserver_stopped() { [[ -z "$(crictl_k8s ps --name kube-apiserver -q)" ]]; }
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/kube-apiserver.yaml
wait_for "the API server stopped" 300 apiserver_stopped

sudo etcdutl snapshot restore "$OLD_BACKUP" --data-dir "$RESTORE_DIR" >/dev/null 2>&1
sudo sed -i "s|path: /var/lib/etcd$|path: ${RESTORE_DIR}|" "$ETCD_MANIFEST"
# The kubelet restarts etcd on its own; the restored data has `legacy`, the old data does not.
etcd_restored() {
  [[ "$(etcdctl_k8s get "/registry/configmaps/${LAB_NS}/legacy" --keys-only 2>/dev/null)" == "/registry/configmaps/${LAB_NS}/legacy"* ]]
}
wait_for "etcd serves the restored data" 600 etcd_restored

# Task 4: start the API server again, so it reads the restored data from scratch
sudo mv /etc/kubernetes/kube-apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml
api_ready() { kubectl get --raw /readyz >/dev/null 2>&1; }
wait_for "the API server ready" 600 api_ready
all_ready() {
  [[ "$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status} {end}' 2>/dev/null)" == "True True True " ]]
}
wait_for "all nodes Ready" 600 all_ready
