# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # variables come from the sourcing script and lab.env
# Shared by setup, verify, solve, and teardown. Sourced after lib.sh and lab.env.

NAMESPACES=(ch33-apps ch33-legacy ch33-sandbox)
STATE="${here}/.state"

# etcdctl against the cluster's etcd, with the client certificate kubeadm created.
etcdctl_k8s() {
  sudo etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key "$@"
}

# etcd_prefix <key>   the first 23 bytes of the value etcd stores under <key>
etcd_prefix() {
  local json value
  json="$(etcdctl_k8s get "$1" -w json 2>/dev/null)" || return 1
  value="$(sed -n 's/.*"value":"\([^"]*\)".*/\1/p' <<<"$json")"
  [[ -n "$value" ]] || return 1
  value="$(base64 -d <<<"$value" 2>/dev/null | tr -d '\0' | cut -c1-23)"
  printf '%s' "${value%%$'\n'*}"
}

# The API server runs with an encryption configuration.
apiserver_encrypts() {
  sudo grep -q -- '--encryption-provider-config=' "$APISERVER_MANIFEST"
}
