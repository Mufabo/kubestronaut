#!/usr/bin/env bash
# Remove the lab's Namespace, answer file, and Falco rule. Audit logging (Task 1)
# and Falco itself stay; restore the snapshot on the host to undo them.
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
lab_teardown_ns "$LAB_NS"
# shellcheck disable=SC2029
if on node1 "test -e ${FALCO_RULES}"; then
  on node1 "sudo rm -f ${FALCO_RULES} && sudo systemctl restart ${FALCO_UNIT}"
fi
rm -f "$FALCO_FILE" "${STATE}/suspect" "${STATE}/miner-uid"
lab_restore_kubectx "${STATE}/kubectx"
info "Lab removed. Audit logging and Falco stay; to undo them, restore the snapshot on the host: envs/vagrant/kbook-vm restore ${LAB_SNAPSHOT}"
