#!/usr/bin/env bash
# Remove the lab's Namespace and answer file, and undo the changes on the nodes:
# the planted service, user ops, both profiles, and seccompDefault on node2.
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
clean_nodes
rm -f "$SERVICE_FILE" "${STATE}/service"
lab_restore_kubectx "${STATE}/kubectx"
info "Lab removed, and node1 and node2 are back as they were."
