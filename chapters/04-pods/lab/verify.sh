#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

jp() { kubectl -n "$LAB_NS" get pod "$1" -o "jsonpath=$2"; }
# The task text says "single container"; a sneaky extra container must not pass.
only_one_container() { [[ "$(jp "$1" '{.spec.containers[*].name}' | wc -w | tr -d '[:space:]')" == "1" ]]; }

t1() {
  only_one_container web &&
  [[ "$(jp web '{.status.phase}')" == "Running" ]] &&
  [[ "$(jp web '{.spec.containers[0].image}')" == "nginx:1.27" ]] &&
  [[ "$(jp web '{.metadata.labels.app}')" == "web" ]] &&
  [[ "$(jp web '{.spec.containers[0].ports[0].containerPort}')" == "80" ]]
}
t2() {
  only_one_container broken &&
  [[ "$(jp broken '{.status.phase}')" == "Running" ]] &&
  [[ "$(jp broken '{.spec.containers[0].image}')" == "nginx:1.27" ]] &&
  # "without deleting and recreating it": the Pod must keep its setup-time UID
  [[ -f "${here}/.state/broken-uid" && "$(jp broken '{.metadata.uid}')" == "$(cat "${here}/.state/broken-uid")" ]]
}
t3() {
  [[ -f "$LAB_ANSWER_FILE" ]] &&
  [[ "$(tr -d '[:space:]' < "$LAB_ANSWER_FILE")" == "$(cat "${here}/.state/code")" ]]
}
t4() {
  only_one_container limited &&
  [[ "$(jp limited '{.spec.containers[0].resources.requests.cpu}')" == "100m" ]] &&
  [[ "$(jp limited '{.spec.containers[0].resources.requests.memory}')" == "64Mi" ]] &&
  [[ "$(jp limited '{.spec.containers[0].resources.limits.cpu}')" == "200m" ]] &&
  [[ "$(jp limited '{.spec.containers[0].resources.limits.memory}')" == "128Mi" ]] &&
  [[ "$(jp limited '{.status.phase}')" == "Running" ]]
}
t5() {
  only_one_container once &&
  [[ "$(jp once '{.spec.restartPolicy}')" == "Never" ]] &&
  [[ "$(jp once '{.status.phase}')" == "Succeeded" ]] &&
  [[ "$(kubectl -n "$LAB_NS" logs once)" == "hello" ]]
}

check 1 "pod 'web' runs nginx:1.27 with label app=web and containerPort 80" \
  "compare 'kubectl get pod web -o yaml' with the task text" t1
check 2 "pod 'broken' is Running with image nginx:1.27, and is the same Pod (not recreated)" \
  "'kubectl describe pod broken' shows why it cannot start; look at the Events" t2
check 3 "the activation code from pod 'logger' is saved in ${LAB_ANSWER_FILE}" \
  "the file should contain only the value after the '='" t3
check 4 "pod 'limited' has the requested CPU/memory requests and limits and is Running" \
  "requests and limits live under spec.containers[].resources" t4
check 5 "pod 'once' ran to completion once, printed hello, and restartPolicy is Never" \
  "a Pod that should not be restarted needs a different restartPolicy" t5

finish_checks
