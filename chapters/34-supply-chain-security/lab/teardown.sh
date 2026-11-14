#!/usr/bin/env bash
# End the lab: remove its Namespaces, the cluster-scoped policy and binding, the local
# registry, the files of Tasks 3 to 6, and restore the reader's kubectl context if they
# changed it.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
lab_teardown_ns "$LAB_SCAN_NS"
kubectl delete validatingadmissionpolicybinding "$LAB_BINDING" --ignore-not-found >/dev/null
kubectl delete validatingadmissionpolicy "$LAB_POLICY" --ignore-not-found >/dev/null
docker rm -f "$LAB_REGISTRY_CONTAINER" >/dev/null 2>&1 || true
rm -f "$LAB_DIGEST_FILE" "$LAB_CRITICAL_FILE" "$LAB_COSIGN_KEY" "$LAB_COSIGN_PUB" "${here}/.state/scan-images"
lab_restore_kubectx "${here}/.state/kubectx"
info "Lab removed."
