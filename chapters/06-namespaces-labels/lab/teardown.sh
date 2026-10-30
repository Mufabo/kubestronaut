#!/usr/bin/env bash
# End the lab: remove its namespaces, the node label, and the answer files, and
# restore the reader's kubectl context/namespace if they opted in with
# `make use-namespace`.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

require_lab_cluster
remove_lab_state
lab_restore_kubectx "${STATE}/kubectx"
info "Lab removed."
