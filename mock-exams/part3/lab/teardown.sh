#!/usr/bin/env bash
# End the exam: remove its namespaces, cluster-wide objects, contexts, and answer
# files, and restore the reader's kubectl context. The upgrade and the node2
# fault stay; restore the snapshot on the host to undo them.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

require_snapshot "$LAB_SNAPSHOT"
require_lab_cluster
lab_restore_kubectx "${STATE}/kubectx"
remove_exam
info "Exam removed; your kubectl context is restored. To undo the upgrade and the node2 fault: envs/vagrant/kbook-vm restore ${LAB_SNAPSHOT}"
