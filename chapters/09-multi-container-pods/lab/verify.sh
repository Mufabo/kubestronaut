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
# has_text <pod> <container> <path> <text>: the file's content is exactly <text>
has_text() {
  local out
  out="$(k exec "$1" -c "$2" -- cat "$3" 2>/dev/null)" || return 1
  [[ "$out" == "$4" ]]
}

t1() {
  [[ "$(jp pod/pair '{.spec.containers[*].name}')" == "writer reader" ]] &&
  [[ "$(jp pod/pair '{.status.containerStatuses[*].ready}')" == "true true" ]] &&
  [[ -n "$(jp pod/pair '{.spec.volumes[?(@.name=="shared")].emptyDir}')" ]] &&
  k exec pair -c writer -- test -d /shared 2>/dev/null &&
  k exec pair -c reader -- test -d /shared 2>/dev/null &&
  # the reader sees what the writer wrote, so the directory really is shared
  k exec pair -c reader -- test -s /shared/out.txt 2>/dev/null
}

t2() {
  [[ "$(jp pod/setup '{.status.initContainerStatuses[?(@.name=="prepare")].state.terminated.reason}')" == Completed ]] &&
  [[ "$(jp pod/setup '{.spec.containers[*].name}')" == app ]] &&
  [[ "$(jp pod/setup '{.status.containerStatuses[?(@.name=="app")].ready}')" == true ]] &&
  has_text setup app /work/status.txt ready
}

t3() {
  [[ "$(jp pod/checked '{.status.phase}')" == Running ]] &&
  [[ "$(jp pod/checked '{.spec.initContainers[*].name}')" == check ]] &&
  [[ "$(jp pod/checked '{.status.initContainerStatuses[?(@.name=="check")].state.terminated.exitCode}')" == 0 ]] &&
  [[ "$(jp pod/checked '{.status.containerStatuses[?(@.name=="main")].ready}')" == true ]]
}

t4() {
  # the shipper is a native sidecar: an init container that keeps running
  [[ "$(jp pod/logged '{.spec.initContainers[?(@.name=="shipper")].restartPolicy}')" == Always ]] &&
  [[ "$(jp pod/logged '{.spec.containers[*].name}')" == app ]] &&
  [[ "$(jp pod/logged '{.status.initContainerStatuses[?(@.name=="shipper")].started}')" == true ]] &&
  [[ "$(jp pod/logged '{.status.containerStatuses[?(@.name=="app")].ready}')" == true ]] &&
  k exec logged -c shipper -- test -s /var/log/app/app.log 2>/dev/null
}

t5() {
  [[ "$(jp pod/debug '{.spec.shareProcessNamespace}')" == true ]] &&
  [[ "$(jp pod/debug '{.spec.containers[*].name}')" == "app helper" ]] || return 1
  # from helper, both containers' sleep processes are visible
  local out n
  out="$(k exec debug -c helper -- ps 2>/dev/null)" || return 1
  n="$(grep -c 'sleep 3600' <<<"$out" || true)"
  [[ "$n" -ge 2 ]]
}

# Task 6: a DaemonSet with a Ready Pod on every node it may use, the control plane included
t6() {
  local want ready cp pods pod node
  [[ "$(jp daemonset/node-agent '{.spec.template.metadata.labels.app}')" == node-agent ]] &&
  [[ "$(jp daemonset/node-agent '{.spec.template.spec.containers[?(@.name=="agent")].image}')" == busybox:1.36 ]] &&
  [[ "$(jp daemonset/node-agent '{.spec.template.spec.containers[?(@.name=="agent")].env[?(@.name=="NODE_NAME")].valueFrom.fieldRef.fieldPath}')" == spec.nodeName ]] &&
  [[ "$(jp daemonset/node-agent '{.spec.template.spec.tolerations[?(@.key=="node-role.kubernetes.io/control-plane")].effect}')" == *NoSchedule* ]] &&
  want="$(jp daemonset/node-agent '{.status.desiredNumberScheduled}')" &&
  ready="$(jp daemonset/node-agent '{.status.numberReady}')" &&
  [[ -n "$want" && "$want" -gt 0 && "$ready" == "$want" ]] &&
  cp="$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)" &&
  pods="$(k get pods -l app=node-agent -o jsonpath='{range .items[*]}{.metadata.name} {.spec.nodeName}{"\n"}{end}' 2>/dev/null)" &&
  grep -q " ${cp}$" <<<"$pods" || return 1
  while read -r pod node; do
    [[ "$(k logs "$pod" -c agent 2>/dev/null)" == "agent on ${node}" ]] || return 1
  done <<<"$pods"
}

check 1 "Pod pair has containers writer and reader, sharing an emptyDir mounted at /shared" \
  "both containers must mount the same volume; the reader must see the writer's file" t1
check 2 "Pod setup: init container prepare writes 'ready' to /work/status.txt, and app sees it" \
  "init containers run to completion before the app container starts" t2
check 3 "Pod checked runs; its init container check exits 0; the main container is ready" \
  "an init container's spec cannot change in place, so the Pod must be replaced" t3
check 4 "Pod logged: shipper is a native sidecar (init container with restartPolicy Always), and app is ready" \
  "a native sidecar is an initContainers entry with restartPolicy: Always" t4
check 5 "Pod debug shares its process namespace: helper sees the app container's processes" \
  "spec.shareProcessNamespace: true, and both containers must be in the same Pod" t5

check 6 "DaemonSet node-agent (busybox:1.36, NODE_NAME from spec.nodeName, control-plane toleration) has a Ready Pod on every node it may use, the control plane included, each logging its node" \
  "a DaemonSet has no replicas; tolerate node-role.kubernetes.io/control-plane:NoSchedule to reach the control plane node" t6

finish_checks
