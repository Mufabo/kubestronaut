#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

k() { kubectl -n "$LAB_NS" "$@"; }
# jp <resource> <jsonpath>
jp() { k get "$1" -o "jsonpath=$2" 2>/dev/null; }
cluster_jp() { kubectl get "$1" -o "jsonpath=$2" 2>/dev/null; }
# mounts_claim <pod> <claim> <path>: the Pod mounts that claim at that path
mounts_claim() {
  local vol
  vol="$(jp "pod/$1" "{.spec.volumes[?(@.persistentVolumeClaim.claimName==\"$2\")].name}")"
  [[ -n "$vol" ]] || return 1
  [[ "$(jp "pod/$1" "{.spec.containers[0].volumeMounts[?(@.name==\"$vol\")].mountPath}")" == "$3" ]]
}

t1() {
  [[ "$(jp pvc/data-claim '{.status.phase}')" == Bound ]] &&
  [[ "$(jp pvc/data-claim '{.spec.resources.requests.storage}')" == 100Mi ]] || return 1
  # The file is in the claim, so it counts whichever Pod mounts the claim now:
  # Task 2 deletes writer, and the check must still pass after that.
  local user=writer
  k get pod writer >/dev/null 2>&1 || user=reader
  [[ "$(jp "pod/$user" '{.status.phase}')" == Running ]] &&
  mounts_claim "$user" data-claim /data &&
  [[ "$(k exec "$user" -- cat /data/hello.txt 2>/dev/null)" == stored ]]
}

t2() {
  ! k get pod writer >/dev/null 2>&1 &&
  [[ "$(jp pod/reader '{.status.phase}')" == Running ]] &&
  mounts_claim reader data-claim /data &&
  [[ "$(k exec reader -- cat /data/hello.txt 2>/dev/null)" == stored ]]
}

t3() {
  [[ "$(cluster_jp pv/ch13-manual-pv '{.spec.storageClassName}')" == manual ]] &&
  [[ "$(cluster_jp pv/ch13-manual-pv '{.spec.capacity.storage}')" == 1Gi ]] &&
  [[ "$(cluster_jp pv/ch13-manual-pv '{.spec.persistentVolumeReclaimPolicy}')" == Retain ]] &&
  [[ "$(cluster_jp pv/ch13-manual-pv '{.spec.hostPath.path}')" == /mnt/ch13-data ]] &&
  [[ "$(cluster_jp pv/ch13-manual-pv '{.status.phase}')" == Bound ]] &&
  [[ "$(jp pvc/manual-claim '{.status.phase}')" == Bound ]] &&
  [[ "$(jp pvc/manual-claim '{.spec.volumeName}')" == ch13-manual-pv ]] &&
  [[ "$(jp pvc/manual-claim '{.spec.storageClassName}')" == manual ]] &&
  [[ "$(jp pvc/manual-claim '{.spec.resources.requests.storage}')" == 500Mi ]]
}

t4() {
  [[ "$(jp pod/scratch '{.status.phase}')" == Running ]] &&
  [[ "$(jp pod/scratch '{.spec.volumes[?(@.name=="cache")].emptyDir.sizeLimit}')" == 10Mi ]] &&
  mounts_claim_empty scratch cache /cache
}
# mounts_claim_empty <pod> <volume> <path>: the Pod mounts that volume at that path
mounts_claim_empty() {
  [[ "$(jp "pod/$1" "{.spec.containers[0].volumeMounts[?(@.name==\"$2\")].mountPath}")" == "$3" ]]
}

t5() {
  [[ "$(cluster_jp storageclass/ch13-retain '{.provisioner}')" == rancher.io/local-path ]] &&
  [[ "$(cluster_jp storageclass/ch13-retain '{.reclaimPolicy}')" == Retain ]] &&
  [[ "$(cluster_jp storageclass/ch13-retain '{.volumeBindingMode}')" == WaitForFirstConsumer ]] &&
  [[ "$(jp pvc/retained '{.spec.storageClassName}')" == ch13-retain ]] &&
  [[ "$(jp pvc/retained '{.status.phase}')" == Bound ]] &&
  [[ "$(jp pod/retained-user '{.status.phase}')" == Running ]] &&
  mounts_claim retained-user retained /data &&
  [[ "$(cluster_jp "pv/$(jp pvc/retained '{.spec.volumeName}')" '{.spec.persistentVolumeReclaimPolicy}')" == Retain ]]
}

check 1 "PVC data-claim (100Mi, Bound) is mounted by Pod writer at /data, which holds 'stored' in hello.txt" \
  "write the file with: kubectl -n ${LAB_NS} exec writer -- sh -c 'echo stored > /data/hello.txt'" t1
check 2 "Pod writer is gone; Pod reader mounts data-claim at /data and reads the same 'stored'" \
  "a claim outlives the Pods that use it: delete writer first, then create reader" t2
check 3 "PV ch13-manual-pv (1Gi, Retain, hostPath /mnt/ch13-data) is Bound to PVC manual-claim (500Mi)" \
  "a static PV is matched to a claim by storageClassName, capacity and access mode" t3
check 4 "Pod scratch mounts an emptyDir at /cache with sizeLimit 10Mi, and is Running" \
  "the sizeLimit belongs to the emptyDir volume, not to the container" t4
check 5 "StorageClass ch13-retain (Retain, WaitForFirstConsumer); PVC retained is Bound to a Retain volume, used by retained-user" \
  "a WaitForFirstConsumer claim stays Pending until a Pod that uses it is scheduled" t5

finish_checks
