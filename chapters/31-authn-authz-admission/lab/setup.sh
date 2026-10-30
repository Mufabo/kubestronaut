#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
lab_teardown_ns "$LAB_PSA_NS"
# Cluster-scoped leftovers from a previous run.
kubectl delete validatingadmissionpolicybinding "$LAB_BINDING" --ignore-not-found >/dev/null
kubectl delete validatingadmissionpolicy "$LAB_POLICY" --ignore-not-found >/dev/null
rm -f "$LAB_TOKEN_FILE"
lab_create_ns "$LAB_NS"
lab_create_ns "$LAB_PSA_NS"

# The starting state: a ServiceAccount, and no policy or Pod Security label yet.
kubectl -n "$LAB_NS" create serviceaccount ci-bot >/dev/null

info "Lab ready. Namespaces: ${LAB_NS} and ${LAB_PSA_NS}. ServiceAccount ci-bot exists; no policy yet"
