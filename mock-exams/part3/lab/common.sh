# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # variables come from the sourcing script and lab.env
# Shared names for the Part III simulator. Sourced by the lab scripts.

STATE="${here}/.state"
MANIFESTS="${here}/../manifests"
NAMESPACES=(p3-sched p3-ops p3-net p3-data p3-apps)
CTX_A=p3-a
CTX_B=p3-b
DROPIN=/usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf

base_context() { printf '%s' "$LAB_CONTEXT"; }

# ctx_field <context> <field>   a field of a context from the kubeconfig
ctx_field() { kubectl config view -o "jsonpath={.contexts[?(@.name==\"$1\")].context.$2}"; }

leave_exam_contexts() {
  local cur
  cur="$(kubectl config current-context 2>/dev/null || true)"
  if [[ "$cur" == "$CTX_A" || "$cur" == "$CTX_B" ]]; then
    kubectl config use-context "$(base_context)" >/dev/null
  fi
}

# Runs a command string on a node: locally on cp1, over SSH on the workers.
on() { if [[ "$1" == cp1 ]]; then bash -c "$2"; else ssh -o BatchMode=yes "$1" "$2"; fi; }

crictl_k8s() { sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock "$@" 2>/dev/null; }

etcdctl_k8s() {
  sudo etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key "$@"
}

node_ready() {
  [[ "$(kubectl get node "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == True ]]
}

# Everything the exam creates, or asks the reader to create, outside its namespaces too.
# The upgrade (Question 4) and the kubelet fault (Question 15) stay: only a snapshot restore undoes them.
remove_exam() {
  leave_exam_contexts
  lab_delete_contexts "$CTX_A" "$CTX_B"
  info "Removing namespaces ${NAMESPACES[*]} and the exam's cluster-wide objects (if present)"
  kubectl delete namespace "${NAMESPACES[@]}" --ignore-not-found --wait=true --timeout=300s >/dev/null
  kubectl delete persistentvolume logs-pv --ignore-not-found >/dev/null
  kubectl delete clusterrolebinding auditor-nodes --ignore-not-found >/dev/null
  kubectl delete clusterrole node-reader --ignore-not-found >/dev/null
  kubectl delete customresourcedefinition backups.ops.kbook.io --ignore-not-found >/dev/null
  sudo rm -f /etc/kubernetes/manifests/ops-monitor.yaml
  if course_dir_ok "$COURSE"; then sudo rm -rf "$COURSE"; fi   # Question 6 leaves a root-owned file
  rm -f "${STATE}/start" "${STATE}/marker-rv"
}
