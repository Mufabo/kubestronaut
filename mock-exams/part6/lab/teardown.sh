#!/usr/bin/env bash
# End the exam: remove its context, its answer files, and the cluster it built.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
if [[ "$(kubectl config current-context 2>/dev/null || true)" == "$CTX" ]]; then
  kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true
fi
lab_delete_contexts "$CTX"
lab_course_remove "$COURSE"
rm -f "${STATE}/start"
bash "${BOOK_ROOT}/tools/cluster.sh" down
info "Exam removed; make cluster builds the default cluster again."
