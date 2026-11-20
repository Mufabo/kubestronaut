#!/usr/bin/env bash
# Remove the outside server, the answer folder, and the cluster this lab built
# (its nodes were changed by hand, so it is not worth keeping).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
docker rm -f ch48-outside >/dev/null 2>&1 || true
lab_course_remove "$LAB_ANSWERS"
rm -f "${here}/.state/outside-ip"
bash "${BOOK_ROOT}/tools/cluster.sh" down
info "the nocni cluster is gone; make cluster builds the default one again (or the next lab builds its own profile)"
