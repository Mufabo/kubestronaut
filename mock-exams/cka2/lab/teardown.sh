#!/usr/bin/env bash
# End the exam: remove its namespaces, contexts, cluster-wide objects, and answer
# files, repair node2's kubelet, and restore the reader's kubectl context. For a
# fully fresh cluster, restore the snapshot on the host instead.
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
wait_for "node2 Ready" 300 node_ready node2
info "Exam removed; your kubectl context is restored."
