#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require
code="$(cat "${here}/.state/code" 2>/dev/null || true)"
udp_port="$(cat "${here}/.state/udp-port" 2>/dev/null || true)"

t1() { [[ -n "$code" ]] && answer_is "${LAB_ANSWERS}/greeting" "$code"; }
t2() { [[ -n "$udp_port" ]] && answer_is "${LAB_ANSWERS}/udp-port" "$udp_port"; }
t3() { http_says client http://10.0.6.20:9090/ "hello from app"; }
# curl exit code 7 = connection refused (immediately); 28 = timed out.
t4() {
  local rc=0
  nl_ns client curl -s --max-time 3 -o /dev/null http://10.0.6.20:8081/ || rc=$?
  ((rc == 7))
}

check 1 "the TCP greeter's message is in ${LAB_ANSWERS}/greeting" \
  "List listening TCP sockets on the server (ss -ltn), then connect to the unknown port with nc" t1
check 2 "the UDP service's port is in ${LAB_ANSWERS}/udp-port" \
  "ss shows UDP sockets with -u instead of -t" t2
check 3 "the client can fetch http://10.0.6.20:9090/ from the app" \
  "Which address does the app listen on (ss -ltnp)? Stop it and start it again on all addresses" t3
check 4 "connections from the client to port 8081 are refused immediately instead of timing out" \
  "Something on the server drops the SYNs silently: iptables -L INPUT -n -v. DROP makes clients wait; REJECT answers" t4
finish_checks
