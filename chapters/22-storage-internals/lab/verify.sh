#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

k() { kubectl -n "$LAB_NS" "$@"; }
jp() { k get "$1" -o "jsonpath=$2" 2>/dev/null; }
cjp() { kubectl get "$1" -o "jsonpath=$2" 2>/dev/null; }
# file_is <path> <text>: the file holds exactly <text>, ignoring surrounding whitespace
file_is() { [[ -f "$1" ]] && [[ "$(tr -d '[:space:]' < "$1")" == "$2" ]]; }

t1() {
  local pv
  [[ "$(jp pvc/app-data '{.status.phase}')" == Bound ]] || return 1
  pv="$(jp pvc/app-data '{.spec.volumeName}')"
  [[ "$pv" == pvc-* ]] || return 1                       # created by dynamic provisioning
  [[ "$(cjp "pv/$pv" '{.spec.claimRef.name}')" == app-data ]] || return 1
  [[ "$(jp pod/writer '{.status.phase}')" == Running ]] || return 1
  file_is "$LAB_ANSWER_PV" "$pv"
}

t2() {
  local pv
  pv="$(jp pvc/app-data '{.spec.volumeName}')"
  [[ -n "$pv" ]] || return 1
  file_is "$LAB_ANSWER_RECLAIM" "$(cjp "pv/$pv" '{.spec.persistentVolumeReclaimPolicy}')" &&
  [[ "$(cjp "pv/$pv" '{.spec.persistentVolumeReclaimPolicy}')" == "$(cjp storageclass/standard '{.reclaimPolicy}')" ]]
}

t3() {
  [[ "$(jp pvc/shared '{.spec.accessModes[0]}')" == ReadWriteMany ]] || return 1
  [[ "$(jp pvc/shared '{.status.phase}')" == Pending ]] || return 1
  file_is "$LAB_ANSWER_SHARED" Pending
}

t4() {
  [[ "$(cjp "storageclass/$LAB_SC_EXPANDABLE" '{.allowVolumeExpansion}')" == true ]] &&
  [[ "$(cjp "storageclass/$LAB_SC_EXPANDABLE" '{.volumeBindingMode}')" == WaitForFirstConsumer ]] &&
  [[ "$(cjp "storageclass/$LAB_SC_EXPANDABLE" '{.provisioner}')" == rancher.io/local-path ]]
}

t5() {
  local n
  n="$(kubectl get csidrivers --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')"
  file_is "$LAB_ANSWER_CSI" "$n"
}

check 1 "PVC app-data is Bound to a dynamically provisioned PV; /tmp/ch22-pv.txt names that PV" \
  "a claim with the default class and a Pod that mounts it; the PV name starts with pvc-" t1
check 2 "/tmp/ch22-reclaim.txt holds the reclaim policy of the PV bound to app-data (from the class)" \
  "kubectl get pv NAME -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'" t2
check 3 "PVC shared (ReadWriteMany on ${LAB_SC_IMMEDIATE}) is Pending; /tmp/ch22-shared.txt says Pending" \
  "the local-path provisioner supports ReadWriteOnce only" t3
check 4 "StorageClass ${LAB_SC_EXPANDABLE}: allowVolumeExpansion true, WaitForFirstConsumer, provisioner rancher.io/local-path" \
  "allowVolumeExpansion is a StorageClass field, and it must be true before a claim can grow" t4
check 5 "/tmp/ch22-csi.txt holds the number of CSIDriver objects in the cluster" \
  "kubectl get csidrivers; a CSI driver registers one CSIDriver object" t5

finish_checks
