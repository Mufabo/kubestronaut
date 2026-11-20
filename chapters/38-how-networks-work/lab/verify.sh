#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require
secret="$(cat "${here}/.state/secret" 2>/dev/null || true)"

t1() { link_up client eth0 && link_up server eth0 && can_ping client 10.0.2.20; }
t2() { answer_is "${LAB_ANSWERS}/web-port" 8080; }
# The capture must hold the client's request for the home page, sent to the server.
t3() {
  local out
  out="$(nl tcpdump -n -r "${LAB_ANSWERS}/web.pcap" 'tcp dst port 8080' 2>/dev/null)"
  [[ "$out" == *"10.0.2.10."*" > 10.0.2.20.8080:"*"GET / HTTP"* ]]
}
t4() { [[ -n "$secret" ]] && answer_is "${LAB_ANSWERS}/secret-page" "/secret/${secret}.html"; }

check 1 "client can ping the server (10.0.2.20)" \
  "Which end of the cable is down? Compare: on client ip -br link   and   on server ip -br link" t1
check 2 "the web server's port is in ${LAB_ANSWERS}/web-port" \
  "On the server, list listening TCP sockets: on server ss -ltn" t2
check 3 "${LAB_ANSWERS}/web.pcap holds a GET / request from client to the server" \
  "Run tcpdump with -w on the server in one shell, curl http://10.0.2.20:8080/ from the client in another, then Ctrl+C tcpdump" t3
check 4 "the page requested in mystery.pcap is in ${LAB_ANSWERS}/secret-page" \
  "Read the capture: tcpdump -n -r ${LAB_ANSWERS}/mystery.pcap and look for GET" t4
finish_checks
