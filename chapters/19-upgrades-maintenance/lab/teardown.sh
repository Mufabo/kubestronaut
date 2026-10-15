#!/usr/bin/env bash
# Remove the lab's workload. The upgrade itself stays; restore the snapshot on
# the host to undo it.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_snapshot "$LAB_SNAPSHOT"
require_lab_cluster
lab_teardown_ns "$LAB_NS"
rm -f "${here}/.state/pdb-uid"
lab_restore_kubectx "${here}/.state/kubectx"
info "Lab workload removed. To undo the upgrade, restore the snapshot on the host: envs/vagrant/kbook-vm restore ${LAB_SNAPSHOT}"
