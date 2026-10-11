#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
rm -f "$LAB_ANSWER_PV" "$LAB_ANSWER_RECLAIM" "$LAB_ANSWER_SHARED" "$LAB_ANSWER_CSI"
kubectl delete storageclass "$LAB_SC_IMMEDIATE" "$LAB_SC_EXPANDABLE" --ignore-not-found >/dev/null
lab_create_ns "$LAB_NS"

# A StorageClass that binds at once, so Task 3's claim fails visibly instead of waiting.
kubectl apply -f - >/dev/null <<YAML
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${LAB_SC_IMMEDIATE}
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: Immediate
YAML

info "Lab ready. Namespace: ${LAB_NS}. Default StorageClass: standard. Extra class: ${LAB_SC_IMMEDIATE}"
