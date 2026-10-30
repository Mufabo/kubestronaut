#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

k() { kubectl -n "$LAB_NS" "$@"; }
h() { helm -n "$LAB_NS" "$@"; }
# jp <resource> <jsonpath>
jp() { k get "$1" -o "jsonpath=$2" 2>/dev/null; }
# status_has <release> <text>: helm status of the release contains <text>
status_has() {
  local out
  out="$(h status "$1" 2>/dev/null)" || return 1
  grep -Fq -- "$2" <<<"$out"
}
# history_has <release> <text>: helm history of the release contains <text>
history_has() {
  local out
  out="$(h history "$1" 2>/dev/null)" || return 1
  grep -Fq -- "$2" <<<"$out"
}
# revision_values_have <release> <revision> <text>: the values stored with that revision contain <text>
revision_values_have() {
  local out
  out="$(h get values "$1" --revision "$2" 2>/dev/null)" || return 1
  grep -Fq -- "$3" <<<"$out"
}

# Tasks 1 and 2 check what their revisions recorded, not the current revision:
# later tasks (the rollback) add revisions on top of them.
t1() {
  history_has shop "Install complete" &&
  revision_values_have shop 1 "replicaCount: 2"
}

t2() {
  history_has shop "Upgrade complete" &&
  revision_values_have shop 2 'tag: "1.27"' &&
  revision_values_have shop 2 "replicaCount: 2"
}

t3() {
  history_has shop "Rollback to 1" &&
  [[ "$(jp deployment/shop '{.spec.template.spec.containers[0].image}')" == nginx:1.26 ]]
}

t4() {
  [[ "$(jp deployment/api '{.spec.replicas}')" == 3 ]] &&
  [[ "$(jp deployment/api '{.spec.template.spec.containers[0].image}')" == nginx:1.27 ]] &&
  [[ "$(jp deployment/api '{.metadata.labels.env}')" == prod ]]
}

t5() {
  status_has greeter "STATUS: deployed" &&
  [[ "$(jp configmap/greeter-config '{.data.greeting}')" == hello ]]
}

check 1 "Helm release shop was installed from the chart with replicaCount 2 (revision 1)" \
  "helm -n ${LAB_NS} install shop lab/.state/charts/shop --set replicaCount=2" t1
check 2 "Revision 2 of shop upgrades image.tag to 1.27 and keeps replicaCount 2" \
  "helm upgrade with --reuse-values keeps the other values; only image.tag changes" t2
check 3 "Revision 3 of shop is a rollback to revision 1, and runs nginx:1.26 again" \
  "helm rollback creates a new revision; check helm history for the description" t3
check 4 "Kustomize overlay applies api with 3 replicas, nginx:1.27 and the label env=prod" \
  "apply the overlay with kubectl apply -k; the overlay's files are in lab/.state/kustomize" t4
check 5 "Second release greeter stores greeting=hello in its ConfigMap greeter-config" \
  "the chart reads .Values.greeting; set it with --set on install" t5

finish_checks
