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

t1() {
  [[ "$(jp deployment/speed '{.spec.replicas}')" == 3 ]] &&
  [[ "$(jp deployment/speed '{.spec.template.spec.containers[0].image}')" == nginx:1.27 ]] &&
  [[ "$(jp deployment/speed '{.status.readyReplicas}')" == 3 ]]
}

t2() {
  [[ -s "$LAB_JOB_FILE" ]] || return 1
  [[ "$(yq '.kind' "$LAB_JOB_FILE" 2>/dev/null)" == Job ]] &&
  [[ "$(yq '.metadata.name' "$LAB_JOB_FILE" 2>/dev/null)" == count ]] &&
  [[ "$(yq '.spec.template.spec.containers[0].image' "$LAB_JOB_FILE" 2>/dev/null)" == busybox:1.36 ]] &&
  [[ "$(jp job/count '{.status.succeeded}')" == 1 ]]
}

t3() {
  [[ -f "$LAB_RESTARTED_FILE" ]] || return 1
  local want got
  # The Pods that have restarted, computed from the cluster, sorted one per line.
  want="$(k get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].restartCount}{"\n"}{end}' 2>/dev/null |
    awk '$2 > 0 {print $1}' | sort)"
  got="$(sort "$LAB_RESTARTED_FILE" | tr -d '\r')"
  [[ -n "$want" && "$got" == "$want" ]]
}

t4() {
  [[ -s "$LAB_BASE_FILE" && -s "$LAB_SCALED_FILE" ]] || return 1
  [[ "$(yq '.kind' "$LAB_SCALED_FILE" 2>/dev/null)" == Deployment ]] &&
  [[ "$(yq '.metadata.name' "$LAB_SCALED_FILE" 2>/dev/null)" == shop ]] &&
  [[ "$(yq '.spec.replicas' "$LAB_SCALED_FILE" 2>/dev/null)" == 5 ]] &&
  [[ "$(yq '.spec.template.spec.containers[0].image' "$LAB_SCALED_FILE" 2>/dev/null)" == nginx:1.27 ]] &&
  [[ "$(yq '.spec.replicas' "$LAB_BASE_FILE" 2>/dev/null)" == 2 ]]
}

check 1 "Deployment speed in ${LAB_NS} runs nginx:1.27 with 3 ready replicas" \
  "kubectl create deployment speed --image=nginx:1.27, then kubectl scale --replicas=3" t1
check 2 "Job count is saved as ${LAB_JOB_FILE} and has completed" \
  "kubectl create job count --image=busybox:1.36 --dry-run=client -o yaml -- sh -c 'echo 1' > file, then kubectl apply -f file" t2
check 3 "${LAB_RESTARTED_FILE} lists the Pods that have restarted, one per line" \
  "jq or a jsonpath range over .items, filtering restartCount greater than 0" t3
check 4 "${LAB_SCALED_FILE} is the base Deployment with 5 replicas, and the base file is unchanged" \
  "copy the base file, then yq -i '.spec.replicas = 5' on the copy; do not scale the cluster" t4

finish_checks
