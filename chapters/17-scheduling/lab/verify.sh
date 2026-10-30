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

k() { kubectl -n "$LAB_NS" "$@"; }
# jp <resource> <jsonpath>
jp() { k get "$1" -o "jsonpath=$2" 2>/dev/null; }
cjp() { kubectl get "$1" -o "jsonpath=$2" 2>/dev/null; }

t1() {
  [[ "$(jp pod/pinned '{.spec.nodeSelector.disk}')" == ssd ]] &&
  [[ "$(jp pod/pinned '{.spec.nodeName}')" == "$WORKER_A" ]] &&
  [[ "$(jp pod/pinned '{.status.phase}')" == Running ]]
}

t2() {
  [[ "$(jp pod/tolerant '{.spec.nodeName}')" == "$WORKER_B" ]] &&
  [[ "$(jp pod/tolerant '{.spec.tolerations[?(@.key=="maintenance")].effect}')" == NoSchedule ]] &&
  [[ "$(jp pod/tolerant '{.spec.tolerations[?(@.key=="maintenance")].value}')" == true ]] &&
  [[ "$(jp pod/tolerant '{.status.phase}')" == Running ]]
}

t3() {
  [[ "$(jp deployment/cache '{.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].topologyKey}')" == kubernetes.io/hostname ]] &&
  [[ "$(jp deployment/cache '{.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].labelSelector.matchLabels.app}')" == cache ]] &&
  [[ "$(jp deployment/cache '{.status.readyReplicas}')" == 1 ]]
}

t4() {
  [[ "$(cjp priorityclass/"$LAB_PRIORITYCLASS" '{.value}')" == 100000 ]] &&
  [[ "$(jp pod/urgent '{.spec.priorityClassName}')" == "$LAB_PRIORITYCLASS" ]] &&
  [[ "$(jp pod/urgent '{.status.phase}')" == Running ]]
}

t5() {
  [[ -f "$LAB_ANSWER_FILE" ]] && [[ "$(tr -d '[:space:]' < "$LAB_ANSWER_FILE")" == "kube-scheduler-${CLUSTER_NAME}-control-plane" ]]
}

check 1 "Pod pinned runs on ${WORKER_A} because of its disk=ssd selector" \
  "nodeSelector: {disk: ssd} in the Pod spec; the node label is set by setup" t1
check 2 "Pod tolerant runs on ${WORKER_B}, with a toleration for maintenance=true:NoSchedule" \
  "the taint keeps Pods off the node unless they tolerate it; a nodeSelector sends this one there" t2
check 3 "Deployment cache: required pod anti-affinity on hostname for app=cache, one ready replica" \
  "requiredDuringSchedulingIgnoredDuringExecution sits under spec.template.spec.affinity" t3
check 4 "PriorityClass ${LAB_PRIORITYCLASS} has value 100000; Pod urgent uses it and runs" \
  "priorityClassName is a Pod spec field, and the class is cluster-scoped" t4
check 5 "${LAB_ANSWER_FILE} names the static Pod that runs the kube-scheduler" \
  "static Pods are listed in kube-system; their owner is the Node, not a controller" t5

finish_checks
