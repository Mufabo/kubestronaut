#!/usr/bin/env bash
# End the lab: remove everything it created, its answer files, the StorageClasses it
# made, and restore the reader's kubectl context/namespace if they opted in with
# `make use-namespace`. Dynamically provisioned PVs with reclaim policy Delete go
# with their claims; Retain volumes stay and must be deleted by hand.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
kubectl delete storageclass "$LAB_SC_IMMEDIATE" "$LAB_SC_EXPANDABLE" --ignore-not-found >/dev/null
rm -f "$LAB_ANSWER_PV" "$LAB_ANSWER_RECLAIM" "$LAB_ANSWER_SHARED" "$LAB_ANSWER_CSI"
lab_restore_kubectx "${here}/.state/kubectx"
info "Lab removed."
