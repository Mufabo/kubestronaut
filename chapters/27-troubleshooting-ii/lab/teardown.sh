#!/usr/bin/env bash
# Remove the lab's Namespace and answer file. The faults setup injected, and
# any certificate you renewed, stay; restore the snapshot on the host for that.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_snapshot "$LAB_SNAPSHOT"
require_lab_cluster
lab_teardown_ns "$LAB_NS"
rm -f "$CA_EXPIRY_FILE" "${here}/.state/apiserver-not-after"
lab_restore_kubectx "${here}/.state/kubectx"
info "Lab removed. To undo the faults and the renewal, restore the snapshot on the host: envs/vagrant/kbook-vm restore ${LAB_SNAPSHOT}"
