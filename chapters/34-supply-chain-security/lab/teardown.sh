#!/usr/bin/env bash
# End the lab: remove its Namespace, the cluster-scoped policy and binding, the digest
# file, and restore the reader's kubectl context if they changed it.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
kubectl delete validatingadmissionpolicybinding "$LAB_BINDING" --ignore-not-found >/dev/null
kubectl delete validatingadmissionpolicy "$LAB_POLICY" --ignore-not-found >/dev/null
rm -f "$LAB_DIGEST_FILE"
lab_restore_kubectx "${here}/.state/kubectx"
info "Lab removed."
