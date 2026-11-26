#!/usr/bin/env bash
# End the lab: remove everything it created and restore the reader's kubectl
# context/namespace if they opted in with `make use-namespace`.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
kubectl delete pv "$LAB_PV" --ignore-not-found --wait=true --timeout=60s >/dev/null
# The lab's class keeps its volumes (reclaim policy Retain), so the volume that
# Task 5 provisions outlives the namespace: remove every PV of that class too.
retained="$(kubectl get pv -o jsonpath='{range .items[?(@.spec.storageClassName=="'"$LAB_STORAGECLASS"'")]}{.metadata.name}{" "}{end}')"
if [[ -n "${retained// /}" ]]; then
  # shellcheck disable=SC2086  # intentional word splitting of a name list
  kubectl delete pv $retained --ignore-not-found --wait=true --timeout=60s >/dev/null
fi
kubectl delete storageclass "$LAB_STORAGECLASS" --ignore-not-found >/dev/null
lab_restore_kubectx "${here}/.state/kubectx"
info "Lab removed."
