#!/usr/bin/env bash
# End the lab: remove its Namespace, the answer files in /tmp/ch37, and restore the reader's
# kubectl context if they changed it.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
rm -f "$LAB_JOB_FILE" "$LAB_RESTARTED_FILE" "$LAB_SCALED_FILE" "$LAB_BASE_FILE"
rmdir "$LAB_ANSWER_DIR" 2>/dev/null || true
lab_restore_kubectx "${here}/.state/kubectx"
info "Lab removed."
