# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # variables come from the sourcing script and lab.env
# Shared names for the CKAD simulator, set 2. Sourced by the lab scripts.

STATE="${here}/.state"
NAMESPACES=(ckad2-design ckad2-deploy ckad2-ops ckad2-sec ckad2-quota ckad2-net)
CTX_A=ckad2-a
CTX_B=ckad2-b

# The kubectl context the exam contexts are cloned from.
base_context() { printf '%s' "kind-${CLUSTER_NAME}"; }

# ctx_field <context> <field>   a field of a context from the kubeconfig
ctx_field() { kubectl config view -o "jsonpath={.contexts[?(@.name==\"$1\")].context.$2}"; }

# Make sure we are not sitting on a context we are about to delete.
leave_exam_contexts() {
  local cur
  cur="$(kubectl config current-context 2>/dev/null || true)"
  if [[ "$cur" == "$CTX_A" || "$cur" == "$CTX_B" ]]; then
    kubectl config use-context "$(base_context)" >/dev/null
  fi
}

remove_exam() {
  leave_exam_contexts
  lab_delete_contexts "$CTX_A" "$CTX_B"
  info "Removing namespaces ${NAMESPACES[*]} (if present)"
  kubectl delete namespace "${NAMESPACES[@]}" --ignore-not-found --wait=true --timeout=180s >/dev/null
  if command -v docker >/dev/null 2>&1; then
    docker rmi -f "$CKAD_IMAGE" >/dev/null 2>&1 || true
  fi
  lab_course_remove "$COURSE"
  rm -f "${STATE}/start"
}
