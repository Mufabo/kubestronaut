#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_snapshot "$LAB_SNAPSHOT"
require_lab_cluster

# jp <resource> <jsonpath>, in the lab's Namespace
jp() { kubectl -n "$LAB_NS" get "$1" -o "jsonpath=$2" 2>/dev/null; }
# running <pod>: the Pod is Running and its container is ready
running() {
  [[ "$(jp "pod/$1" '{.status.phase}/{.status.containerStatuses[0].ready}')" == Running/true ]]
}
# seccomp_mode <pod>: the Seccomp line of the container's main process (0 none, 2 filter)
seccomp_mode() {
  local out
  out="$(kubectl -n "$LAB_NS" exec "$1" -- grep '^Seccomp:' /proc/1/status 2>/dev/null)" || return 1
  printf '%s' "${out//[!0-9]/}"
}

t1() {
  local service enabled
  service="$(planted_service)"
  [[ -n "$service" && -f "$SERVICE_FILE" && "$(cat "$SERVICE_FILE")" == "${service}.service" ]] || return 1
  [[ "$(on node1 "systemctl is-active ${service}")" != active ]] || return 1
  enabled="$(on node1 "systemctl is-enabled ${service}")"
  [[ "$enabled" == disabled || "$enabled" == masked* ]] || return 1
  [[ -z "$(on node1 "sudo ss -Htln 'sport = :${LEGACY_PORT}'")" ]]
}

t2() {
  local out
  on node1 "id ops" >/dev/null 2>&1 || return 1
  out="$(on node1 "sudo -l -U ops" 2>&1)"
  [[ "$out" == *"is not allowed to run sudo"* ]]
}

t3() {
  [[ "$(jp pod/guarded '{.spec.nodeName}/{.spec.containers[0].image}')" == node1/busybox:1.36 ]] || return 1
  running guarded || return 1
  [[ "$(kubectl -n "$LAB_NS" exec guarded -- cat /proc/1/attr/current 2>/dev/null)" == "${APPARMOR_PROFILE} (enforce)" ]]
}

t4() {
  local profile out
  [[ "$(jp pod/locked '{.spec.nodeName}/{.spec.containers[0].image}')" == node1/busybox:1.36 ]] || return 1
  # The container's own setting wins over the Pod's.
  profile="$(jp pod/locked '{.spec.containers[0].securityContext.seccompProfile.type}:{.spec.containers[0].securityContext.seccompProfile.localhostProfile}')"
  [[ "$profile" != : ]] || profile="$(jp pod/locked '{.spec.securityContext.seccompProfile.type}:{.spec.securityContext.seccompProfile.localhostProfile}')"
  [[ "$profile" == "Localhost:${SECCOMP_PROFILE}" ]] || return 1
  running locked || return 1
  [[ "$(seccomp_mode locked)" == 2 ]] || return 1
  # chmod to the mode /tmp already has: harmless where it is allowed, refused under the profile.
  out="$(kubectl -n "$LAB_NS" exec locked -- chmod 1777 /tmp 2>&1)" && return 1
  [[ "$out" == *"Operation not permitted"* ]]
}

t5() {
  [[ "$(jp pod/plain '{.spec.nodeName}/{.spec.containers[0].image}')" == node2/busybox:1.36 ]] || return 1
  [[ -z "$(jp pod/plain '{.spec.securityContext.seccompProfile}{.spec.containers[*].securityContext.seccompProfile}')" ]] || return 1
  running plain || return 1
  [[ "$(seccomp_mode plain)" == 2 ]]
}

check 1 "the service listening on node1:${LEGACY_PORT} is stopped and disabled, and its unit name is in ${SERVICE_FILE}" \
  "on node1: sudo ss -tlnp shows the process; ps -o unit= -p <pid> names its unit" t1
check 2 "user ops on node1 still exists and may not run anything with sudo" \
  "look in /etc/sudoers.d and at the groups of ops; sudo -l -U ops shows what it may do" t2
check 3 "Pod guarded runs on node1 under the AppArmor profile ${APPARMOR_PROFILE}, in enforce mode" \
  "load the profile on node1 with apparmor_parser, then set securityContext.appArmorProfile" t3
check 4 "Pod locked runs on node1 with the Localhost seccomp profile ${SECCOMP_PROFILE}, and chmod fails in it" \
  "the profile file belongs under ${SECCOMP_DIR}/ on node1; localhostProfile is relative to that directory" t4
check 5 "Pod plain runs on node2 under seccomp without a seccompProfile in its spec" \
  "seccompDefault in node2's kubelet configuration, then recreate the Pod" t5

finish_checks
