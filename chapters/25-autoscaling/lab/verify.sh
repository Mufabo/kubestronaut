#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

k() { kubectl -n "$LAB_NS" "$@"; }
jp() { k get "$1" -o "jsonpath=$2" 2>/dev/null; }
file_is() { [[ -f "$1" ]] && [[ "$(tr -d '[:space:]' < "$1")" == "$2" ]]; }

t1() {
  [[ "$(jp hpa/api '{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}')" == Deployment/api ]] &&
  [[ "$(jp hpa/api '{.spec.minReplicas}/{.spec.maxReplicas}')" == 1/4 ]] &&
  [[ "$(jp hpa/api '{.spec.metrics[0].resource.name}/{.spec.metrics[0].resource.target.averageUtilization}')" == cpu/50 ]]
}

t2() {
  [[ "$(jp deployment/api '{.status.readyReplicas}')" -ge 2 ]] 2>/dev/null
}

t3() {
  # the controller has read the metric: the status names the resource it observed
  [[ "$(jp hpa/api '{.status.currentMetrics[0].resource.name}')" == cpu ]] || return 1
  file_is "$LAB_ANSWER_METRIC" cpu
}

t4() {
  [[ "$(jp hpa/api '{.spec.behavior.scaleDown.stabilizationWindowSeconds}')" == 60 ]]
}

t5() {
  local want
  want="$(kubectl api-resources --api-group=autoscaling --no-headers 2>/dev/null | awk '$NF=="HorizontalPodAutoscaler"{print $3}')"
  [[ -n "$want" ]] && file_is "$LAB_ANSWER_HPA_API" "$want"
}

check 1 "HPA api targets Deployment api, 1 to 4 replicas, cpu averageUtilization 50" \
  "autoscaling/v2 spec: scaleTargetRef, minReplicas, maxReplicas, metrics[0].resource" t1
check 2 "Deployment api scaled to at least 2 ready replicas under its CPU load" \
  "the HPA raises replicas when utilization is above the target; wait a minute and read readyReplicas" t2
check 3 "The HPA reports the cpu metric it observed; ${LAB_ANSWER_METRIC} holds cpu" \
  "kubectl get hpa api -o yaml, look at status.currentMetrics" t3
check 4 "HPA api waits 60 seconds before scaling down (behavior.scaleDown.stabilizationWindowSeconds)" \
  "behavior is a field of the HPA spec, under scaleDown" t4
check 5 "${LAB_ANSWER_HPA_API} holds the API version that serves HorizontalPodAutoscalers" \
  "kubectl api-resources --api-group=autoscaling shows the served version" t5

finish_checks
