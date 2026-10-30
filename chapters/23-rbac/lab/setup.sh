#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
# Cluster-scoped leftovers from a previous run.
kubectl delete clusterrolebinding "$LAB_CLUSTERROLEBINDING" --ignore-not-found >/dev/null
kubectl delete clusterrole "$LAB_CLUSTERROLE" --ignore-not-found >/dev/null
rm -f "$LAB_ANSWER_CAN_DELETE"
lab_create_ns "$LAB_NS"

# The starting state: a ServiceAccount with no permissions, which Task 4 changes.
kubectl -n "$LAB_NS" create serviceaccount builder >/dev/null

info "Lab ready. Namespace: ${LAB_NS}. ServiceAccount builder exists; reporter does not yet"
