#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
# Remove only this lab's own state: .state/ also holds the saved kubectl context.
mkdir -p "${here}/.state"
rm -f "${here}/.state/db-password"

lab_create_ns "$LAB_NS"

# A random password the reader must copy into db-credentials (Task 2). It is
# stored only in the Secret legacy-db, so the reader has to decode it.
pw="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 || true)"
[[ ${#pw} -eq 16 ]] || die "failed to generate a 16-character password"
printf '%s' "$pw" > "${here}/.state/db-password"
kubectl -n "$LAB_NS" create secret generic legacy-db --from-literal=password="$pw" >/dev/null

info "Lab ready. Namespace: ${LAB_NS} (use -n ${LAB_NS}, or run: make use-namespace CH=7)"
