#!/usr/bin/env bash
# Remove the cluster this lab built (its nodes were changed).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
bash "${BOOK_ROOT}/tools/cluster.sh" down
info "the lab cluster is gone; make cluster builds the default one again (or the next lab builds its own profile)"
