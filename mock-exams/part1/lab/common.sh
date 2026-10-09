# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # variables come from the sourcing script and lab.env
# Shared names for the Part I simulator. Sourced by the lab scripts.

STATE="${here}/.state"
MANIFESTS="${here}/../manifests"
NAMESPACES=(p1-io p1-europa p1-titan p1-callisto)
CTX_A=p1-a
CTX_B=p1-b

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
  local ns
  leave_exam_contexts
  lab_delete_contexts "$CTX_A" "$CTX_B"
  for ns in "${NAMESPACES[@]}"; do lab_teardown_ns "$ns"; done
  lab_course_remove "$COURSE"
  rm -f "${STATE}/start" "${STATE}/token" "${STATE}/exit-code" "${STATE}/ledger.yaml"
}
