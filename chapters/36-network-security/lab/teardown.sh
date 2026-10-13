#!/usr/bin/env bash
# End the lab: remove its Namespace (and every NetworkPolicy and Secret in it), the
# certificate files, and restore the reader's kubectl context if they changed it.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
rm -f "$LAB_CERT" "$LAB_KEY"
rmdir "$LAB_CERT_DIR" 2>/dev/null || true
lab_restore_kubectx "${here}/.state/kubectx"
info "Lab removed."
