# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # variables come from the sourcing script and lab.env
# Shared by the Chapter 06 lab scripts. Sourced, never executed.

STATE="${here}/.state"

# remove_lab_state   delete everything the lab owns, inside and outside the cluster
remove_lab_state() {
  local node
  # One delete for all namespaces, so they terminate in parallel.
  info "Removing namespaces ${LAB_SNAPSHOT_NS// /, } (if present)"
  # shellcheck disable=SC2086  # intentional word splitting of a name list
  kubectl delete namespace $LAB_SNAPSHOT_NS --ignore-not-found --wait=true --timeout=180s >/dev/null
  # The node label is cluster-scoped: take it off every node that has it.
  for node in $(kubectl get nodes -l "$LAB_NODE_LABEL" -o name); do
    kubectl label "$node" "${LAB_NODE_LABEL}-" >/dev/null
  done
  rm -f "$LAB_ANSWER_NS" "$LAB_ANSWER_PODS"
  rm -f "${STATE}/degraded-uid" "${STATE}/fast-io-uid"
}
