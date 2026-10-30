#!/usr/bin/env bash
# End the lab: remove everything it created, put the nodes back, and restore the
# reader's kubectl context/namespace if they opted in with `make use-namespace`.
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
rm -f "$LAB_ANSWER_FILE"
reset_cluster_scoped
lab_restore_kubectx "${here}/.state/kubectx"
info "Lab removed."
