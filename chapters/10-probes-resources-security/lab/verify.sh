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
# ready <pod>: the Pod's container reports Ready
ready() { [[ "$(jp "pod/$1" '{.status.containerStatuses[0].ready}')" == true ]]; }

t1() {
  [[ "$(jp pod/gate '{.spec.containers[0].readinessProbe.exec.command}')" == '["cat","/tmp/ready"]' ]] &&
  k exec gate -- test -f /tmp/ready 2>/dev/null &&
  ready gate
}

t2() {
  [[ "$(jp pod/healthy '{.spec.containers[0].image}')" == nginx:1.27 ]] &&
  [[ "$(jp pod/healthy '{.spec.containers[0].livenessProbe.httpGet.path}')" == / ]] &&
  [[ "$(jp pod/healthy '{.spec.containers[0].livenessProbe.httpGet.port}')" == 80 ]] &&
  [[ "$(jp pod/healthy '{.spec.containers[0].livenessProbe.initialDelaySeconds}')" == 5 ]] &&
  [[ "$(jp pod/healthy '{.spec.containers[0].livenessProbe.periodSeconds}')" == 10 ]] &&
  ready healthy
}

t3() {
  [[ "$(jp pod/sized '{.spec.containers[0].resources.requests.cpu}')" == 100m ]] &&
  [[ "$(jp pod/sized '{.spec.containers[0].resources.requests.memory}')" == 64Mi ]] &&
  [[ "$(jp pod/sized '{.spec.containers[0].resources.limits.cpu}')" == 200m ]] &&
  [[ "$(jp pod/sized '{.spec.containers[0].resources.limits.memory}')" == 128Mi ]] &&
  [[ "$(jp pod/sized '{.status.qosClass}')" == Burstable ]] &&
  [[ "$(jp pod/sized '{.status.phase}')" == Running ]]
}

t4() {
  [[ "$(jp pod/pinned '{.spec.containers[0].resources.requests.cpu}')" == 250m ]] &&
  [[ "$(jp pod/pinned '{.spec.containers[0].resources.limits.cpu}')" == 250m ]] &&
  [[ "$(jp pod/pinned '{.spec.containers[0].resources.requests.memory}')" == 128Mi ]] &&
  [[ "$(jp pod/pinned '{.spec.containers[0].resources.limits.memory}')" == 128Mi ]] &&
  [[ "$(jp pod/pinned '{.status.qosClass}')" == Guaranteed ]] &&
  [[ "$(jp pod/pinned '{.status.phase}')" == Running ]]
}

t5() {
  [[ "$(jp pod/hardened '{.spec.securityContext.runAsNonRoot}')" == true ]] &&
  [[ "$(jp pod/hardened '{.spec.securityContext.runAsUser}')" == 1000 ]] &&
  [[ "$(jp pod/hardened '{.spec.containers[0].securityContext.allowPrivilegeEscalation}')" == false ]] &&
  [[ "$(jp pod/hardened '{.spec.containers[0].securityContext.capabilities.drop}')" == '["ALL"]' ]] &&
  # the running process really is uid 1000, and holds no capabilities
  [[ "$(k exec hardened -- id -u 2>/dev/null)" == 1000 ]] &&
  [[ "$(k exec hardened -- grep CapEff /proc/1/status 2>/dev/null | awk '{print $2}')" == 0000000000000000 ]]
}

t6() {
  [[ "$(jp limitrange/defaults '{.spec.limits[?(@.type=="Container")].defaultRequest.cpu} {.spec.limits[?(@.type=="Container")].defaultRequest.memory} {.spec.limits[?(@.type=="Container")].default.cpu} {.spec.limits[?(@.type=="Container")].default.memory}')" == "100m 64Mi 200m 128Mi" ]] &&
  [[ "$(jp resourcequota/compute '{.spec.hard.pods} {.spec.hard.requests\.cpu} {.spec.hard.requests\.memory} {.spec.hard.limits\.cpu} {.spec.hard.limits\.memory}')" == "10 2 2Gi 4 4Gi" ]] &&
  # the quota is in force: its controller has filled in what is used
  [[ -n "$(jp resourcequota/compute '{.status.used.pods}')" ]] &&
  [[ "$(jp pod/plain '{.spec.containers[0].image}')" == nginx:1.27 ]] &&
  [[ "$(jp pod/plain '{.spec.containers[0].resources.requests.cpu} {.spec.containers[0].resources.requests.memory} {.spec.containers[0].resources.limits.cpu} {.spec.containers[0].resources.limits.memory}')" == "100m 64Mi 200m 128Mi" ]] &&
  [[ "$(jp pod/plain '{.status.phase}')" == Running ]]
}

check 1 "Pod gate: readiness probe runs cat /tmp/ready; the file exists and the Pod is Ready" \
  "the probe is exec-based: it only passes when /tmp/ready exists inside the container" t1
check 2 "Pod healthy: nginx:1.27, liveness httpGet / on port 80, initialDelay 5s, period 10s; Ready" \
  "the field names are httpGet.path, httpGet.port, initialDelaySeconds, periodSeconds" t2
check 3 "Pod sized: requests 100m/64Mi, limits 200m/128Mi, QoS class Burstable, Running" \
  "a Pod whose requests differ from its limits is Burstable" t3
check 4 "Pod pinned: requests equal limits (250m, 128Mi), QoS class Guaranteed, Running" \
  "Guaranteed needs both CPU and memory requests equal to limits in every container" t4
check 5 "Pod hardened: runs as uid 1000, non-root, no privilege escalation, all capabilities dropped" \
  "pod-level securityContext for runAsUser and runAsNonRoot; container-level for capabilities" t5

check 6 "LimitRange defaults (100m/64Mi requests, 200m/128Mi limits), ResourceQuota compute (10 pods, 2/2Gi requests, 4/4Gi limits), Pod plain runs with the defaults"   "a LimitRange's default and defaultRequest are filled in when a Pod is created; create the LimitRange before the Pod" t6

finish_checks
