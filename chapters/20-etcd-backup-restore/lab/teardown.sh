#!/usr/bin/env bash
# Remove the lab's Namespace and files. A restore cannot be undone in place;
# restore the snapshot on the host for that.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_snapshot "$LAB_SNAPSHOT"
require_lab_cluster
lab_teardown_ns "$LAB_NS"
sudo rm -f "$NEW_BACKUP" "$OLD_BACKUP" "$REVISION_FILE"
rm -f "${here}/.state/current-rv"
lab_restore_kubectx "${here}/.state/kubectx"
info "Lab removed. If etcd runs from ${RESTORE_DIR}, restore the snapshot on the host to undo that: envs/vagrant/kbook-vm restore ${LAB_SNAPSHOT}"
