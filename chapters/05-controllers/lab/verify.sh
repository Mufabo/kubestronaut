#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

jd() { kubectl -n "$LAB_NS" get deployment "$1" -o "jsonpath=$2"; }
# The Deployment's Pods have one container, running the given image.
runs_image() {
  local imgs
  imgs="$(jd "$1" '{.spec.template.spec.containers[*].image}')" && [[ "$imgs" == "$2" ]]
}
# The latest rollout is complete: every wanted replica is updated and available,
# and no Pod of an older revision is left (status.replicas counts old Pods too).
rolled_out() {
  local s gen obs want total upd avail
  s="$(jd "$1" '{.metadata.generation}|{.status.observedGeneration}|{.spec.replicas}|{.status.replicas}|{.status.updatedReplicas}|{.status.availableReplicas}')" || return 1
  IFS='|' read -r gen obs want total upd avail <<<"$s"
  [[ -n "$want" && "$gen" == "$obs" && "$want" == "$total" && "$want" == "$upd" && "$want" == "$avail" ]]
}
same_object() { [[ -f "${here}/.state/$1-uid" && "$(jd "$1" '{.metadata.uid}')" == "$(cat "${here}/.state/$1-uid")" ]]; }

t1() {
  runs_image web nginx:1.27 &&
  [[ "$(jd web '{.spec.replicas}')" == "3" ]] &&
  rolled_out web
}
t2() {
  [[ "$(jd api '{.spec.replicas}')" == "5" ]] &&
  runs_image api nginx:1.26 &&
  rolled_out api
}
t3() {
  same_object frontend &&
  runs_image frontend nginx:1.27 &&
  [[ "$(jd frontend '{.metadata.annotations.kubernetes\.io/change-cause}')" == "upgrade to 1.27" ]] &&
  rolled_out frontend
}
t4() {
  same_object shop &&
  runs_image shop nginx:1.27 &&
  rolled_out shop
}
t5() {
  [[ "$(jd cache '{.spec.strategy.type}')" == "RollingUpdate" ]] &&
  [[ "$(jd cache '{.spec.strategy.rollingUpdate.maxUnavailable}')" == "0" ]] &&
  [[ "$(jd cache '{.spec.strategy.rollingUpdate.maxSurge}')" == "1" ]] &&
  [[ "$(jd cache '{.spec.replicas}')" == "2" ]]
}
# The ReplicaSet owned by Deployment history that currently has Pods.
t6() {
  local rows want
  rows="$(kubectl -n "$LAB_NS" get replicasets -o jsonpath='{range .items[*]}{.metadata.name}|{.metadata.ownerReferences[0].name}|{.spec.replicas}{"\n"}{end}')" &&
  want="$(awk -F'|' '$2=="history" && $3>0 {print $1}' <<<"$rows")" &&
  [[ -n "$want" && "$want" != *$'\n'* && -f "$LAB_ANSWER_FILE" ]] &&
  [[ "$(tr -d '[:space:]' < "$LAB_ANSWER_FILE" | sed 's#^replicaset[^/]*/##')" == "$want" ]]
}

check 1 "Deployment 'web' runs 3 ready replicas of nginx:1.27" \
  "kubectl create deployment has --image and --replicas flags" t1
check 2 "Deployment 'api' is scaled to 5 ready replicas and still runs nginx:1.26" \
  "kubectl scale deployment ... --replicas=..." t2
check 3 "Deployment 'frontend' rolled out nginx:1.27 with change-cause 'upgrade to 1.27'" \
  "kubectl set image needs the container name (it is not 'nginx'); the change-cause is an annotation on the Deployment" t3
check 4 "Deployment 'shop' is back on nginx:1.27 with all replicas available (same Deployment)" \
  "kubectl rollout history shows the revisions; kubectl rollout undo --to-revision=N" t4
check 5 "Deployment 'cache' uses RollingUpdate with maxUnavailable 0 and maxSurge 1" \
  "the settings live under spec.strategy.rollingUpdate; kubectl explain deployment.spec.strategy" t5
check 6 "the ReplicaSet that currently runs history's Pods is named in ${LAB_ANSWER_FILE}" \
  "a Deployment keeps old ReplicaSets at 0 replicas; look at DESIRED in kubectl get rs" t6

finish_checks
