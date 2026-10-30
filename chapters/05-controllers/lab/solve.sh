#!/usr/bin/env bash
# Automated reference solution (used by CI). Human-readable version: solutions.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

k() { kubectl -n "$LAB_NS" "$@"; }

# Task 1
k create deployment web --image=nginx:1.27 --replicas=3 >/dev/null

# Task 2
k scale deployment api --replicas=5 >/dev/null

# Task 3
k set image deployment/frontend web=nginx:1.27 >/dev/null
k annotate deployment frontend kubernetes.io/change-cause="upgrade to 1.27" --overwrite >/dev/null

# Task 4: revision 2 is the last one that ran nginx:1.27
k rollout undo deployment/shop --to-revision=2 >/dev/null

# Task 5
k patch deployment cache -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxUnavailable":0,"maxSurge":1}}}}' >/dev/null

# Task 6
k get replicasets -l app=history -o jsonpath='{range .items[?(@.spec.replicas>0)]}{.metadata.name}{"\n"}{end}' > "$LAB_ANSWER_FILE"

info "Waiting for the rollouts to finish"
for d in web api frontend shop cache; do
  k rollout status "deployment/${d}" --timeout=180s >/dev/null
done
no_terminating() {
  [[ -z "$(k get pods -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.name}{"\n"}{end}')" ]]
}
wait_for "old Pods to finish terminating" 120 no_terminating
