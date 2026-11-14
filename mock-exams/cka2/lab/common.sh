# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # variables come from the sourcing script and lab.env
# Shared names for the CKA simulator, set 2. Sourced by the lab scripts.

STATE="${here}/.state"
MANIFESTS="${here}/../manifests"
NAMESPACES=(cka2-dev cka2-team cka2-apps cka2-legacy cka2-work cka2-net cka2-locked cka2-data cka2-ops)
CTX_A=cka2-a
CTX_B=cka2-b
KUBELET_CONFIG=/var/lib/kubelet/config.yaml
STATIC_POD=/etc/kubernetes/manifests/node-probe.yaml
REPORTS_CRD=reports.cka2.kbook.io

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

node_ready() {
  [[ "$(kubectl get node "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == True ]]
}

etcdctl_k8s() {
  sudo etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key "$@"
}

# Everything the exam creates, or asks the reader to create, outside its namespaces.
remove_exam() {
  leave_exam_contexts
  lab_delete_contexts "$CTX_A" "$CTX_B"
  info "Removing namespaces ${NAMESPACES[*]} and the exam's cluster-wide objects (if present)"
  on node1 "sudo rm -f ${STATIC_POD}" >/dev/null 2>&1 || true
  # Helm keeps its releases as Secrets in their Namespaces, so this removes them too.
  kubectl delete namespace "${NAMESPACES[@]}" --ignore-not-found --wait=true --timeout=300s >/dev/null
  kubectl delete clusterrole cka2-reports-viewer --ignore-not-found >/dev/null
  kubectl delete crd "$REPORTS_CRD" --ignore-not-found >/dev/null
  kubectl delete persistentvolume cka2-archive cka2-reports cka2-shared --ignore-not-found >/dev/null
  kubectl delete gatewayclass cka2-class --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n kube-system delete deployment metrics-server --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete apiservice v1beta1.metrics.k8s.io --ignore-not-found >/dev/null 2>&1 || true
  on node2 "sudo sed -i 's|clientCAFile: /etc/kubernetes/pki/ca-cert.crt|clientCAFile: /etc/kubernetes/pki/ca.crt|' ${KUBELET_CONFIG} && sudo systemctl restart kubelet" >/dev/null 2>&1 || true
  on node1 "sudo rm -rf /srv/cka2-archive /srv/cka2-reports /srv/cka2-shared" >/dev/null 2>&1 || true
  if course_dir_ok "$COURSE"; then sudo rm -rf "$COURSE"; fi
  rm -f "${STATE}/start" "${STATE}/token"
}
