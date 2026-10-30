#!/usr/bin/env bash
# Remove the lab's Namespaces, RuntimeClass, and answer file. Encryption at rest
# (Task 4) and gVisor on the workers stay; restore the snapshot on the host to undo them.
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
for ns in "${NAMESPACES[@]}"; do lab_teardown_ns "$ns"; done
kubectl delete runtimeclass gvisor --ignore-not-found >/dev/null
rm -f "$VIOLATIONS_FILE" "${STATE}/db-pass"
lab_restore_kubectx "${STATE}/kubectx"
info "Lab removed. Encryption at rest and gVisor stay; to undo them, restore the snapshot on the host: envs/vagrant/kbook-vm restore ${LAB_SNAPSHOT}"
