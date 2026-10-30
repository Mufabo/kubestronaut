#!/usr/bin/env bash
# End the lab: remove its namespace, the CRD it created (and every custom object of
# that kind), its answer files, and restore the reader's kubectl context/namespace
# if they opted in with `make use-namespace`.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
remove_operator
kubectl delete crd "$LAB_CRD" --ignore-not-found --wait=true >/dev/null
rm -f "$LAB_ANSWER_VALIDATION" "$LAB_ANSWER_NAMES" "$LAB_ANSWER_CRI"
lab_restore_kubectx "${here}/.state/kubectx"
info "Lab removed."
