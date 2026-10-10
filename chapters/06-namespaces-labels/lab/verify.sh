#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_lab_cluster

jp() { kubectl -n "$1" get pod "$2" -o "jsonpath=$3"; }
# norm_lines <file>   sorted, unique, trimmed, non-empty lines; a leading "pod/" is ignored
norm_lines() { sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's#^pod/##' "$1" | grep -v '^$' | sort -u; }

# Task 1: the namespace lost-cat lives in
t1() {
  local where
  where="$(kubectl get pods -A --field-selector metadata.name=lost-cat -o jsonpath='{.items[*].metadata.namespace}')" &&
  [[ -n "$where" && "$where" != *" "* && -f "$LAB_ANSWER_NS" ]] &&
  [[ "$(tr -d '[:space:]' < "$LAB_ANSWER_NS" | sed 's#^namespace/##')" == "$where" ]]
}

# Task 2: namespace ch06-payments with label team=payments, and Pod ledger in it
t2() {
  [[ "$(kubectl get namespace ch06-payments -o jsonpath='{.metadata.labels.team}')" == "payments" ]] &&
  [[ "$(jp ch06-payments ledger '{.spec.containers[*].image}')" == "nginx:1.27" ]] &&
  [[ "$(jp ch06-payments ledger '{.metadata.labels.app}')" == "ledger" ]] &&
  [[ "$(jp ch06-payments ledger '{.status.phase}')" == "Running" ]]
}

# Task 3: the degraded Pod is released from the Deployment and replaced
t3() {
  local uid rows mine
  uid="$(cat "${STATE}/degraded-uid" 2>/dev/null)" && [[ -n "$uid" ]] &&
  rows="$(kubectl -n "$LAB_NS" get pods -o jsonpath='{range .items[*]}{.metadata.uid}|{.metadata.labels.app}|{.metadata.ownerReferences[*].kind}|{.status.phase}{"\n"}{end}')" &&
  mine="$(awk -F'|' -v u="$uid" '$1==u' <<<"$rows")" &&
  [[ "$mine" == "${uid}|queue-debug||Running" ]] &&
  [[ "$(kubectl -n "$LAB_NS" get deployment queue -o jsonpath='{.spec.replicas}/{.status.readyReplicas}')" == "3/3" ]]
}

# Task 4: the seeded Pods in ch06-shop that are not Running. Only the seeded
# Pods are compared: a queue Pod that Task 3 replaced may be briefly Pending
# when the reader lists them, and listing it too is not wrong.
SEEDED='^(storefront|import-done|import-failed|reports)$'
t4() {
  local rows want given
  rows="$(kubectl -n "$LAB_NS" get pods -o jsonpath='{range .items[*]}{.metadata.name} {.status.phase}{"\n"}{end}')" &&
  want="$(awk '$2!="Running" {print $1}' <<<"$rows" | grep -E "$SEEDED" | sort -u)" &&
  [[ -n "$want" && -f "$LAB_ANSWER_PODS" ]] &&
  given="$(norm_lines "$LAB_ANSWER_PODS" | grep -E "$SEEDED")" &&
  [[ "$given" == "$want" ]]
}

# Task 5: fast-io runs, unchanged, because exactly one node carries disk=ssd
t5() {
  [[ -f "${STATE}/fast-io-uid" && "$(jp ch06-blue fast-io '{.metadata.uid}')" == "$(cat "${STATE}/fast-io-uid")" ]] &&
  [[ "$(jp ch06-blue fast-io '{.status.phase}')" == "Running" ]] &&
  [[ "$(kubectl get nodes -l "${LAB_NODE_LABEL}=ssd" -o name | wc -l | tr -d '[:space:]')" == "1" ]]
}

check 1 "the namespace of Pod lost-cat is saved in ${LAB_ANSWER_NS}" \
  "kubectl get pods -A searches every namespace; a field selector on metadata.name narrows it down" t1
check 2 "namespace ch06-payments (label team=payments) runs Pod ledger (nginx:1.27, label app=ledger)" \
  "kubectl create namespace, kubectl label namespace, then kubectl run ... -n ch06-payments" t2
check 3 "the degraded queue Pod now has app=queue-debug, no owner, and queue is back to 3 ready Pods" \
  "find it with a jsonpath filter on annotations; kubectl label --overwrite changes the value" t3
check 4 "the Pods in ch06-shop that are not Running are listed in ${LAB_ANSWER_PODS}" \
  "kubectl get pods --field-selector status.phase!=Running" t4
check 5 "Pod fast-io runs, and exactly one node has the label ${LAB_NODE_LABEL}=ssd" \
  "kubectl describe pod fast-io shows why it is Pending; label a worker node, not the Pod" t5

finish_checks
