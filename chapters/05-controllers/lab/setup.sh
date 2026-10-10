#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
rm -f "$LAB_ANSWER_FILE"
# Remove only this lab's own files: .state/ also holds the saved kubectl context.
mkdir -p "${here}/.state"
rm -f "${here}/.state/frontend-uid" "${here}/.state/shop-uid"

lab_create_ns "$LAB_NS"
kubectl -n "$LAB_NS" apply -f "${here}/../manifests/seed.yaml" >/dev/null

# rollout <name> <replicas> <image> <change-cause>   apply one revision
rollout() {
  sed -e "s|__NAME__|$1|g" -e "s|__REPLICAS__|$2|" -e "s|__IMAGE__|$3|" -e "s|__CAUSE__|$4|" \
    "${here}/../manifests/rollout.yaml.tpl" | kubectl -n "$LAB_NS" apply -f - >/dev/null
}
# rolled_out <name>   wait until the Deployment's latest rollout is complete
rolled_out() { kubectl -n "$LAB_NS" rollout status "deployment/$1" --timeout=180s >/dev/null; }

# Task 4: shop has three revisions; the last one points at an image that does
# not exist, so its rollout is stuck. Revision 2 is the last good one.
rollout shop 3 nginx:1.26 "initial release"
rolled_out shop
rollout shop 3 nginx:1.27 "upgrade to nginx 1.27"
rolled_out shop
rollout shop 3 nginx:1.27-doesnotexist "try the new build"

# Task 6: history has two revisions, so it owns two ReplicaSets.
rollout history 1 nginx:1.26 "initial release"
rolled_out history
rollout history 1 nginx:1.27 "upgrade to nginx 1.27"

info "Waiting for the Deployments to be ready (image pulls may take a moment)"
for d in api frontend cache history; do rolled_out "$d"; done
# rollout status returns while old Pods are still shutting down; wait for them
# so the lab starts in a settled state.
no_terminating() {
  [[ -z "$(kubectl -n "$LAB_NS" get pods -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.name}{"\n"}{end}')" ]]
}
wait_for "old Pods to finish terminating" 120 no_terminating

# Tasks 3 and 4 must change the Deployments, not replace them: remember them.
kubectl -n "$LAB_NS" get deployment frontend -o jsonpath='{.metadata.uid}' > "${here}/.state/frontend-uid"
kubectl -n "$LAB_NS" get deployment shop -o jsonpath='{.metadata.uid}' > "${here}/.state/shop-uid"

info "Lab ready. Namespace: ${LAB_NS} (use -n ${LAB_NS}, or run: make use-namespace CH=5)"
