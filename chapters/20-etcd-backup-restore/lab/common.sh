# shellcheck shell=bash
# Shared by setup, verify, solve, and teardown. Sourced after lib.sh and lab.env.

# etcdctl against the cluster's etcd, with the client certificate kubeadm created.
etcdctl_k8s() {
  sudo etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key "$@"
}

# The host directory mounted as etcd's data volume in the static Pod manifest.
etcd_data_hostpath() {
  sudo awk '/hostPath:/ {getline; p=$2} /name: etcd-data/ && p {print p; exit}' "$ETCD_MANIFEST"
}
