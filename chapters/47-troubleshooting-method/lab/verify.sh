#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require

lookup() { nl_ns laptop dig +short +time=2 +tries=1 "$@" 2>/dev/null | tail -n 1; }

t1() { [[ "$(lookup @10.11.2.53 dns.corp.internal)" == 10.11.2.53 ]]; }
t2() { [[ "$(lookup app.corp.internal)" == 10.11.2.80 ]]; }
t3() { can_ping laptop 10.11.2.80; }
# curl exit 0 = page, 7 = refused: either way the connection attempt got an
# answer instead of timing out (28).
t4() {
  local rc=0
  nl_ns laptop curl -s --max-time 3 -o /dev/null http://10.11.2.80:8080/ || rc=$?
  ((rc == 0 || rc == 7))
}
t5() { http_says laptop http://app.corp.internal:8080/ "hello from app"; }

check 1 "the laptop gets answers from the DNS server 10.11.2.53" \
  "Name lookups time out. Can the laptop reach 10.11.2.53 at all? Who answers ARP for it on the dc LAN (ip -n r1 neigh)?" t1
check 2 "app.corp.internal resolves to 10.11.2.80 on the laptop" \
  "Compare the DNS answer with the address the app really has (on app ip -br addr); the zone data is in /etc/dns/hosts.corp" t2
check 3 "the laptop can ping the app (10.11.2.80)" \
  "Capture on app: do the requests arrive? Where would app send its replies (on app ip route)?" t3
check 4 "connections from the laptop to 10.11.2.80:8080 get an answer instead of timing out" \
  "Timeouts with working ping: look for a filter on the path. iptables -L -n -v on r1, and watch the counters" t4
check 5 "the laptop gets the app's page from http://app.corp.internal:8080/" \
  "Connection refused: which address does the app listen on (on app ss -ltnp)?" t5
finish_checks
