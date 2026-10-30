#!/usr/bin/env bash
# Build the exam: four namespaces, two contexts, seeded Pods, answer folders.
# Idempotent: it always removes the previous attempt first.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

require_lab_cluster
lab_save_kubectx "${STATE}/kubectx"      # keeps the ORIGINAL on repeat runs
remove_exam
mkdir -p "$STATE"
lab_course_reset "$COURSE" 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18

# Two contexts on the same cluster, like the exam's per-question contexts.
base="$(base_context)"
cluster="$(ctx_field "$base" cluster)"
user="$(ctx_field "$base" user)"
[[ -n "$cluster" && -n "$user" ]] || die "cannot read the cluster and user of context ${base}"
kubectl config set-context "$CTX_A" --cluster="$cluster" --user="$user" >/dev/null
kubectl config set-context "$CTX_B" --cluster="$cluster" --user="$user" --namespace=p1-europa >/dev/null

for ns in "${NAMESPACES[@]}"; do
  [[ "$ns" == p1-staging ]] || lab_create_ns "$ns"    # the reader creates p1-staging (question 15)
done

# Random values, so answers cannot be copied from the solutions.
token="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 10 || true)"
[[ ${#token} -eq 10 ]] || die "failed to generate a token"
printf '%s' "$token" > "${STATE}/token"
code=$((2 + RANDOM % 119))
printf '%s' "$code" > "${STATE}/exit-code"

kubectl -n p1-callisto apply -f "${MANIFESTS}/callisto-pods.yaml" >/dev/null
kubectl -n p1-europa apply -f "${MANIFESTS}/ledger.yaml" >/dev/null
sed "s/__TOKEN__/${token}/" "${MANIFESTS}/beacon.yaml" | kubectl -n p1-titan apply -f - >/dev/null
sed "s/__CODE__/${code}/" "${MANIFESTS}/importer.yaml" | kubectl -n p1-io apply -f - >/dev/null
kubectl apply -f "${MANIFESTS}/rbac.yaml" >/dev/null
kubectl -n p1-ganymede apply -f "${MANIFESTS}/ganymede.yaml" >/dev/null

# Question 16: atlas gets a history whose last revision is broken. About half
# the time an extra good revision comes first, so the broken revision's number
# and the image to roll back to change between runs.
atlas() {
  sed -e "s|__IMAGE__|$1|" -e "s|__CAUSE__|$2|" "${MANIFESTS}/atlas.yaml.tpl" |
    kubectl -n p1-ganymede apply -f - >/dev/null
  [[ "${3:-}" == nowait ]] || kubectl -n p1-ganymede rollout status deployment/atlas --timeout=180s >/dev/null
}
atlas nginx:1.26 "initial release"
atlas nginx:1.27 "upgrade to nginx 1.27"
good=nginx:1.27 broken=3
if ((RANDOM % 2)); then
  atlas nginx:1.26 "back to nginx 1.26 for a bug"
  good=nginx:1.26 broken=4
fi
atlas nginx:1.27-doesnotexist "try the experimental build" nowait
printf '%s' "$good" > "${STATE}/atlas-good-image"
printf '%s' "$broken" > "${STATE}/atlas-broken-revision"

info "Waiting for the seeded Pods (image pulls may take a moment)"
for p in c-web-1 c-web-2 c-db-1 c-db-2 c-cache-1 c-cache-2 c-batch-1 c-misc; do
  wait_for "pod ${p} Running" 240 pod_phase_is p1-callisto "$p" Running
done
wait_for "pod importer finished" 180 pod_phase_is p1-io importer Failed
agent_restarted() {
  local n
  n="$(kubectl -n p1-titan get pod beacon -o jsonpath='{.status.containerStatuses[?(@.name=="agent")].restartCount}')"
  [[ "${n:-0}" -ge 1 ]] &&
  [[ -n "$(kubectl -n p1-titan get pod beacon -o jsonpath='{.status.containerStatuses[?(@.name=="agent")].state.running.startedAt}')" ]]
}
wait_for "beacon's agent container restarted once" 180 agent_restarted
for d in orbit drone; do
  kubectl -n p1-ganymede rollout status "deployment/${d}" --timeout=180s >/dev/null
done
no_terminating() {
  [[ -z "$(kubectl -n p1-ganymede get pods -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.name}{"\n"}{end}')" ]]
}
wait_for "old atlas Pods to finish terminating" 120 no_terminating

# Questions 16 to 18 must change these objects, not replace them.
kubectl -n p1-ganymede get deployment atlas -o jsonpath='{.metadata.uid}' > "${STATE}/atlas-uid"
kubectl -n p1-ganymede get deployment orbit -o jsonpath='{.metadata.uid}' > "${STATE}/orbit-uid"
quarantined="$(kubectl -n p1-ganymede get pods -l app=drone -o jsonpath='{.items[0].metadata.name}')"
kubectl -n p1-ganymede annotate pod "$quarantined" quarantine=yes >/dev/null
kubectl -n p1-ganymede get pod "$quarantined" -o jsonpath='{.metadata.uid}' > "${STATE}/drone-quarantine-uid"

date +%s > "${STATE}/start"       # the clock starts when setup ends
info "Exam ready. You have ${EXAM_MINUTES} minutes; the pass mark is ${EXAM_PASS_PERCENT}%."
info "Questions: mock-exams/part1/part1.md. Score with: make mock-score EXAM=part1"
