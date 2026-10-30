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
kubectl delete validatingadmissionpolicybinding "$LAB_BINDING" --ignore-not-found >/dev/null
kubectl delete validatingadmissionpolicy "$LAB_POLICY" --ignore-not-found >/dev/null
rm -f "$LAB_DIGEST_FILE"
lab_create_ns "$LAB_NS"
# Deleting a policy takes effect in admission a moment later, so wait until a Pod is no longer refused.
wait_for "the previous image policy to stop applying" 60 \
  kubectl -n "$LAB_NS" run policy-probe --image=nginx:1.27 --restart=Never --dry-run=server -- true

# A Pod that already runs before any policy exists. Task 3 reads its image digest.
kubectl -n "$LAB_NS" run runner --image=busybox:1.36 --restart=Never -- sleep 3600 >/dev/null
kubectl -n "$LAB_NS" wait --for=condition=Ready pod/runner --timeout=180s >/dev/null

info "Lab ready. Namespace: ${LAB_NS}. Pod runner runs busybox:1.36. No image policy yet"
