#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

k() { kubectl -n "$LAB_NS" "$@"; }
# jp <resource> <jsonpath>
jp() { k get "$1" -o "jsonpath=$2" 2>/dev/null; }

t1() {
  [[ -f "$LAB_ANSWER_FILE" ]] || return 1
  [[ "$(cat "$LAB_ANSWER_FILE")" == "fatal: missing config DATABASE_URL" ]]
}

t2() {
  [[ "$(jp pod/crasher '{.spec.containers[0].env[?(@.name=="DATABASE_URL")].value}')" == "postgres://db:5432/shop" ]] &&
  [[ "$(jp pod/crasher '{.status.phase}')" == Running ]] &&
  [[ "$(jp pod/crasher '{.status.containerStatuses[0].ready}')" == true ]]
}

t3() {
  [[ -f "$LAB_LOG_FILE" ]] || return 1
  # two Pods x three lines each, every line from the order log
  local lines matched
  lines="$(wc -l < "$LAB_LOG_FILE" | tr -d '[:space:]')"
  matched="$(grep -c 'order processed id=' "$LAB_LOG_FILE" || true)"
  [[ "$lines" == 6 && "$matched" == 6 ]]
}

t4() {
  [[ "$(jp deployment/checkout '{.spec.template.metadata.annotations.observability\.example\.com/scrape}')" == true ]] &&
  [[ "$(jp deployment/checkout '{.status.readyReplicas}')" == 2 ]]
}

t5() {
  [[ "$(jp pdb/checkout-pdb '{.apiVersion}')" == policy/v1 ]] &&
  [[ "$(jp pdb/checkout-pdb '{.spec.minAvailable}')" == 1 ]] &&
  [[ "$(jp pdb/checkout-pdb '{.spec.selector.matchLabels.app}')" == checkout ]]
}

check 1 "File $LAB_ANSWER_FILE holds the fatal line the crasher Pod printed" \
  "the line is printed by the failing run; read it from the logs (current or --previous)" t1
check 2 "Pod crasher runs with DATABASE_URL=postgres://db:5432/shop, and is Ready" \
  "the Pod's environment cannot change in place, so replace it with the same name" t2
check 3 "File $LAB_LOG_FILE holds the last 3 lines of each checkout Pod (6 lines)" \
  "a label selector reads every matching Pod; --tail limits lines per Pod" t3
check 4 "Deployment checkout's Pod template has the annotation observability.example.com/scrape=true, rolled out" \
  "a template annotation changes the Pods, so it rolls out; a metadata annotation would not" t4
check 5 "PodDisruptionBudget checkout-pdb: policy/v1, minAvailable 1, selector app=checkout" \
  "policy/v1beta1 is not served on this cluster; use kubectl api-resources to find the served version" t5

finish_checks
