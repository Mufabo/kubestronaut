#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_snapshot "$LAB_SNAPSHOT"
require_lab_cluster

# The revision recorded in a snapshot file, or nothing if it is not a valid snapshot.
snapshot_revision() {
  sudo test -f "$1" &&
  sudo etcdutl snapshot status "$1" -w json 2>/dev/null | sed -nE 's/.*"revision":([0-9]+).*/\1/p'
}

# Task 1: a valid snapshot of the cluster, taken after the lab started
t1() {
  local rev since
  rev="$(snapshot_revision "$NEW_BACKUP")" && [[ -n "$rev" ]] &&
  since="$(cat "${here}/.state/current-rv" 2>/dev/null)" && [[ -n "$since" ]] &&
  ((rev >= since))
}

# Task 2: the revision of that snapshot, and nothing else, in the answer file
t2() {
  local rev
  rev="$(snapshot_revision "$NEW_BACKUP")" && [[ -n "$rev" ]] &&
  [[ "$(tr -d '[:space:]' < "$REVISION_FILE" 2>/dev/null)" == "$rev" ]]
}

# Task 3: etcd runs from the restore directory, and is healthy
t3() {
  [[ "$(etcd_data_hostpath)" == "$RESTORE_DIR" ]] &&
  sudo test -d "${RESTORE_DIR}/member/snap" &&
  etcdctl_k8s endpoint health >/dev/null 2>&1
}

# Task 4: the cluster's data is the older backup's: legacy is back, current is gone, all nodes Ready.
# Both a get and a list must agree: a list from an API server that was not restarted still shows the old data.
t4() {
  local ready names
  kubectl -n "$LAB_NS" get configmap legacy >/dev/null 2>&1 &&
  ! kubectl -n "$LAB_NS" get configmap current >/dev/null 2>&1 &&
  names="$(kubectl -n "$LAB_NS" get configmaps -o name)" &&
  grep -qx configmap/legacy <<<"$names" &&
  ! grep -qx configmap/current <<<"$names" &&
  ready="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Ready")].status} {end}')" &&
  [[ "$ready" == "cp1=True node1=True node2=True " ]]
}

check 1 "${NEW_BACKUP} is a valid etcd snapshot, taken after the lab started" \
  "etcdctl snapshot save, with --endpoints, --cacert, --cert, and --key from the etcd manifest (use sudo)" t1
check 2 "${REVISION_FILE} holds the revision of ${NEW_BACKUP}, and nothing else" \
  "etcdutl snapshot status FILE -w table (etcdctl no longer has a status command)" t2
check 3 "etcd runs from ${RESTORE_DIR} (its data hostPath) and reports healthy" \
  "etcdutl snapshot restore ${OLD_BACKUP} --data-dir ${RESTORE_DIR}, then point the etcd-data hostPath in ${ETCD_MANIFEST} at it" t3
check 4 "the cluster holds the older backup's data (ConfigMap legacy exists, current does not), and all three nodes are Ready" \
  "stop the API server (move its manifest out of /etc/kubernetes/manifests) before the restore, and start it again after etcd runs from the new directory" t4

finish_checks
