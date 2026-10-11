#!/usr/bin/env bash
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
lab_create_ns "$LAB_NS"

# The starting state: one worker is labelled for SSD storage, the other is
# tainted for maintenance, so Pods need a selector or a toleration to land there.
kubectl label node "$WORKER_A" disk=ssd --overwrite >/dev/null
kubectl taint node "$WORKER_B" maintenance=true:NoSchedule --overwrite >/dev/null

info "Lab ready. Namespace: ${LAB_NS}. ${WORKER_A} is labelled disk=ssd; ${WORKER_B} is tainted maintenance=true:NoSchedule"
