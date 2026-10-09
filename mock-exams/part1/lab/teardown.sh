#!/usr/bin/env bash
# End the exam: remove its namespaces, contexts, and answer files, and restore
# the reader's kubectl context and namespace.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

require_lab_cluster
lab_restore_kubectx "${STATE}/kubectx"
remove_exam
info "Exam removed; your kubectl context is restored."
