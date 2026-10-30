# shellcheck shell=bash
# shellcheck disable=SC2034  # variables come from the sourcing script
# Node names and the cluster-scoped state this lab changes.
WORKER_A="${CLUSTER_NAME}-worker"
WORKER_B="${CLUSTER_NAME}-worker2"

# reset_cluster_scoped: the labels, taints and PriorityClass the lab owns go back to
# the starting state. Safe to run repeatedly.
reset_cluster_scoped() {
  kubectl label node "$WORKER_A" disk- --overwrite >/dev/null 2>&1 || true
  kubectl label node "$WORKER_B" disk- --overwrite >/dev/null 2>&1 || true
  kubectl taint node "$WORKER_B" maintenance- >/dev/null 2>&1 || true
  kubectl delete priorityclass "$LAB_PRIORITYCLASS" --ignore-not-found >/dev/null
}
