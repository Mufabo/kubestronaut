# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # variables come from the sourcing script and lab.env
# Shared names for the CKA simulator. Sourced by the lab scripts.

STATE="${here}/.state"
MANIFESTS="${here}/../manifests"
NAMESPACES=(cka-team cka-infra cka-work cka-net cka-data cka-ops)
CTX_A=cka-a
CTX_B=cka-b
# Question 15: a second scheduler, run as a static Pod on cp1.
SCHED_MANIFEST=/etc/kubernetes/manifests/cka-scheduler.yaml
SCHED_CONFIG=/etc/kubernetes/cka-scheduler-config.yaml

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

# The serial of the certificate the API server serves on this node.
served_apiserver_serial() {
  openssl s_client -connect 127.0.0.1:6443 </dev/null 2>/dev/null | openssl x509 -noout -serial 2>/dev/null
}

# Everything the exam creates, or asks the reader to create, outside its namespaces.
# A renewed API server certificate (question 3) stays: it is valid, and only a
# snapshot restore takes it back.
remove_exam() {
  leave_exam_contexts
  lab_delete_contexts "$CTX_A" "$CTX_B"
  info "Removing namespaces ${NAMESPACES[*]} and the exam's cluster-wide objects (if present)"
  sudo rm -f "$SCHED_MANIFEST" "$SCHED_CONFIG"
  kubectl delete namespace "${NAMESPACES[@]}" --ignore-not-found --wait=true --timeout=300s >/dev/null
  kubectl delete certificatesigningrequest jane --ignore-not-found >/dev/null
  kubectl delete priorityclass cka-high --ignore-not-found >/dev/null
  kubectl delete persistentvolume fast-pv archive-pv --ignore-not-found >/dev/null
  kubectl delete storageclass local-wait --ignore-not-found >/dev/null
  kubectl delete gatewayclass cka-class --ignore-not-found >/dev/null 2>&1 || true
  kubectl label node node2 tier- role- >/dev/null 2>&1 || true
  kubectl label node node1 role- >/dev/null 2>&1 || true
  if [[ -f "${STATE}/Corefile" ]]; then
    kubectl -n kube-system create configmap coredns --from-file=Corefile="${STATE}/Corefile" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  fi
  on node1 "sudo systemctl enable --now containerd" >/dev/null 2>&1 || true
  on node2 "sudo rm -rf /srv/cka-fast /srv/cka-archive" >/dev/null 2>&1 || true
  if course_dir_ok "$COURSE"; then sudo rm -rf "$COURSE"; fi
  rm -f "${STATE}/start" "${STATE}/apiserver-serial"
}
