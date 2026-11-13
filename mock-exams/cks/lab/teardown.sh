#!/usr/bin/env bash
# End the exam: remove its namespaces, contexts, cluster-wide objects, node files,
# and answer files, turn NodeRestriction back on, and restore the reader's kubectl
# context. Encryption at rest and audit logging (questions 8 and 13) stay; for a
# fully fresh cluster, restore the snapshot on the host instead.
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
if sudo grep -q -- '--enable-admission-plugins=ServiceAccount$' "$APISERVER_MANIFEST"; then
  info "Turning NodeRestriction back on (the API server restarts, about a minute)"
  sudo sed -i 's/--enable-admission-plugins=ServiceAccount$/--enable-admission-plugins=NodeRestriction/' "$APISERVER_MANIFEST"
  wait_for "the API server with NodeRestriction" 300 apiserver_restarted_with --enable-admission-plugins=NodeRestriction
fi
info "Exam removed; your kubectl context is restored."
