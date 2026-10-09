#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

# Strip whitespace and a leading "kind/" prefix (as printed by `-o name`).
norm_token() { tr -d '[:space:]' < "$1" | sed 's#^[A-Za-z]*/##'; }
# Sorted, de-duplicated, non-empty lines with any "pod/" prefix removed.
norm_lines() { grep -v '^[[:space:]]*$' "$1" | sed 's#^[A-Za-z]*/##' | tr -d '\r' | sort -u; }

# answer_is <file> <expected-value>
answer_is() {
  [[ -f "$1" ]] && [[ -n "$2" ]] && [[ "$(norm_token "$1")" == "$2" ]]
}

t1() {
  answer_is "$F_CP" "$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}')"
}
t2() {
  answer_is "$F_ETCD" "$(kubectl -n kube-system get pods -l component=etcd -o jsonpath='{.items[0].metadata.name}')"
}
t3() {
  local expected
  expected="$(kubectl -n kube-system get pods -o jsonpath='{range .items[?(@.metadata.ownerReferences[0].kind=="Node")]}{.metadata.name}{"\n"}{end}' | sort -u)"
  [[ -f "$F_STATIC" ]] && [[ -n "$expected" ]] && [[ "$(norm_lines "$F_STATIC")" == "$expected" ]]
}
t4() {
  answer_is "$F_NODE" "$(kubectl -n "$LAB_NS" get pod where-am-i -o jsonpath='{.spec.nodeName}')"
}
t5() {
  # Not norm_token: it would strip the "apps/" prefix that is part of the answer.
  local served
  [[ -f "$F_API" ]] && [[ "$(tr -d '[:space:]' < "$F_API")" == "apps/v1" ]] &&
  served="$(kubectl api-resources --api-group=apps -o name)" &&
  grep -qx 'deployments.apps' <<<"$served"
}

check 1 "the control plane node's name is saved in ${F_CP}" \
  "nodes carry a role label; try 'kubectl get nodes --show-labels'" t1
check 2 "the name of the etcd Pod is saved in ${F_ETCD}" \
  "control plane components run as Pods in the kube-system namespace" t2
check 3 "the names of all static Pods in kube-system are in ${F_STATIC}, one per line" \
  "static Pods appear as mirror Pods; look at their owner (kubectl get pod <name> -o yaml)" t3
check 4 "the node running the where-am-i Pod is saved in ${F_NODE}" \
  "'kubectl get pods -o wide' shows the node" t4
check 5 "the API group/version serving Deployments (group/version form) is saved in ${F_API}" \
  "'kubectl api-resources' lists the group and version for each resource" t5

finish_checks
