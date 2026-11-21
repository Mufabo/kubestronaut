#!/usr/bin/env bash
# Remove the answer folder and the cluster this lab built (a node was changed).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
lab_course_remove "$LAB_ANSWERS"
bash "${BOOK_ROOT}/tools/cluster.sh" down
info "the lab cluster is gone; make cluster builds the default one again (or the next lab builds its own profile)"
