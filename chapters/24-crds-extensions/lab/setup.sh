#!/usr/bin/env bash
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
# The CRD is cluster-scoped: remove the leftovers of a previous run. Deleting it
# also deletes every custom object of that kind.
kubectl delete crd "$LAB_CRD" --ignore-not-found --wait=true >/dev/null
rm -f "$LAB_ANSWER_VALIDATION" "$LAB_ANSWER_NAMES" "$LAB_ANSWER_CRI"
lab_create_ns "$LAB_NS"

info "Lab ready. Namespace: ${LAB_NS}. The CRD ${LAB_CRD} does not exist yet"
