#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

require_lab_cluster
remove_lab_state
mkdir -p "$STATE"

lab_create_ns "$LAB_NS"
# shellcheck disable=SC2086  # intentional word splitting of a name list
for ns in $LAB_COLOR_NS; do lab_create_ns "$ns"; done

kubectl -n "$LAB_NS" apply -f "${here}/../manifests/shop.yaml" >/dev/null
kubectl -n ch06-blue apply -f "${here}/../manifests/fast-io.yaml" >/dev/null

# Task 1: two pets per colour namespace, and lost-cat in a random one of them.
pet() { sed "s/__NAME__/$2/" "${here}/../manifests/cat.yaml.tpl" | kubectl -n "$1" apply -f - >/dev/null; }
pet ch06-red tom;      pet ch06-red felix
pet ch06-green garfield; pet ch06-green salem
pet ch06-blue binx;    pet ch06-blue luna
read -ra colors <<<"$LAB_COLOR_NS"
pet "${colors[RANDOM % ${#colors[@]}]}" lost-cat

info "Waiting for the Pods to start (image pulls may take a moment)"
wait_for "storefront Running" 180 pod_phase_is "$LAB_NS" storefront Running
wait_for "import-done Succeeded" 180 pod_phase_is "$LAB_NS" import-done Succeeded
wait_for "import-failed Failed" 180 pod_phase_is "$LAB_NS" import-failed Failed
kubectl -n "$LAB_NS" rollout status deployment/queue --timeout=180s >/dev/null
# Only the pets: fast-io in ch06-blue stays Pending on purpose (Task 5).
pets_running() { [[ -z "$(kubectl -n "$1" get pods -l app=pets --field-selector=status.phase!=Running -o name)" ]]; }
for ns in "${colors[@]}"; do
  wait_for "pets in ${ns} Running" 180 pets_running "$ns"
done

# Task 3: mark one queue Pod as degraded and remember which one.
degraded="$(kubectl -n "$LAB_NS" get pods -l app=queue -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "$LAB_NS" annotate pod "$degraded" status=degraded >/dev/null
kubectl -n "$LAB_NS" get pod "$degraded" -o jsonpath='{.metadata.uid}' > "${STATE}/degraded-uid"

# Task 5: fast-io must be scheduled as it is, not recreated.
kubectl -n ch06-blue get pod fast-io -o jsonpath='{.metadata.uid}' > "${STATE}/fast-io-uid"

info "Lab ready. Namespaces: ${LAB_NS}, ${LAB_COLOR_NS// /, } (use -n, or run: make use-namespace CH=6)"
