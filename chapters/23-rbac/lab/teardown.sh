#!/usr/bin/env bash
# End the lab: remove everything it created (including the cluster-scoped roles and
# bindings), its answer file, and restore the reader's kubectl context/namespace if
# they opted in with `make use-namespace`.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
kubectl delete clusterrolebinding "$LAB_CLUSTERROLEBINDING" --ignore-not-found >/dev/null
kubectl delete clusterrole "$LAB_CLUSTERROLE" --ignore-not-found >/dev/null
rm -f "$LAB_ANSWER_CAN_DELETE"
lab_restore_kubectx "${here}/.state/kubectx"
info "Lab removed."
