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
# condition <job> <type> <status> [reason]: the Job reports this condition
condition() {
  local out
  out="$(jp "job/$1" '{.status.conditions[?(@.type=="'"$2"'")].status}')" || return 1
  [[ "$out" == "$3" ]] || return 1
  [[ -z "${4:-}" ]] || [[ "$(jp "job/$1" '{.status.conditions[?(@.type=="'"$2"'")].reason}')" == "$4" ]]
}

t1() {
  [[ "$(jp job/report '{.spec.completions}')" == 1 ]] &&
  condition report Complete True &&
  # the output of the Job's one Pod
  out="$(k logs job/report 2>/dev/null)" && grep -Fxq -- "report done" <<<"$out"
}

t2() {
  [[ "$(jp job/batch '{.spec.completions}')" == 6 ]] &&
  [[ "$(jp job/batch '{.spec.parallelism}')" == 2 ]] &&
  [[ "$(jp job/batch '{.spec.template.spec.containers[0].image}')" == busybox:1.36 ]] &&
  [[ "$(jp job/batch '{.status.succeeded}')" == 6 ]] &&
  condition batch Complete True
}

t3() {
  [[ "$(jp job/fragile '{.spec.backoffLimit}')" == 2 ]] &&
  condition fragile Failed True BackoffLimitExceeded
}

t4() {
  [[ "$(jp cronjob/nightly-report '{.spec.schedule}')" == "30 2 * * *" ]] &&
  [[ "$(jp cronjob/nightly-report '{.spec.concurrencyPolicy}')" == Forbid ]] &&
  [[ "$(jp cronjob/nightly-report '{.spec.successfulJobsHistoryLimit}')" == 2 ]] &&
  [[ "$(jp cronjob/nightly-report '{.spec.jobTemplate.spec.template.spec.containers[0].image}')" == busybox:1.36 ]]
}

t5() {
  # created from the CronJob, so the Job is owned by it
  [[ "$(jp job/manual-run '{.metadata.ownerReferences[0].kind}')" == CronJob ]] &&
  [[ "$(jp job/manual-run '{.metadata.ownerReferences[0].name}')" == nightly-report ]] &&
  condition manual-run Complete True &&
  out="$(k logs job/manual-run 2>/dev/null)" && grep -Fxq -- "nightly report" <<<"$out"
}

check 1 "Job report runs once and prints 'report done'" \
  "kubectl -n ${LAB_NS} get job report; the Job needs a completed Pod, so wait for it" t1
check 2 "Job batch: 6 completions, 2 in parallel, busybox:1.36, all 6 succeeded" \
  "the field names are .spec.completions and .spec.parallelism" t2
check 3 "Job fragile gives up with reason BackoffLimitExceeded after backoffLimit 2" \
  "the Job fails only after its retries; wait about 30 seconds, then check the Failed condition" t3
check 4 "CronJob nightly-report: schedule 30 2 * * *, Forbid, keeps 2 successful Jobs, busybox:1.36" \
  "concurrencyPolicy and successfulJobsHistoryLimit are CronJob fields, not Job fields" t4
check 5 "Job manual-run is created from CronJob nightly-report and completes" \
  "kubectl create job manual-run --from=cronjob/nightly-report" t5

finish_checks
