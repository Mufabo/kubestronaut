#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require

vip_works() { http_says client http://10.96.0.10/ "hello from be"; }
direct_blocked() {
  ! nl_ns client curl -s --max-time 3 -o /dev/null http://10.10.2.11/ 2>/dev/null &&
    ! nl_ns client curl -s --max-time 3 -o /dev/null http://10.10.2.12/ 2>/dev/null
}

t1() { can_ping client 10.10.1.1; }
t2() { vip_works; }
# 20 requests: with a fair 50/50 split, missing a backend has odds of 1 in 500,000.
t3() {
  local seen="" _
  for _ in $(seq 1 20); do seen+="$(http_body client http://10.96.0.10/) "; done
  [[ "$seen" == *"hello from be1"* && "$seen" == *"hello from be2"* ]]
}
t4() { vip_works && direct_blocked; }

check 1 "the client can ping the node (10.10.1.1)" \
  "iptables shows nothing, but iptables is not the only user of netfilter: nft list ruleset" t1
check 2 "the client gets a backend's page from http://10.96.0.10/" \
  "No host owns 10.96.0.10. Rewrite the destination on the node before routing: iptables -t nat -A PREROUTING ... -j DNAT" t2
check 3 "requests to http://10.96.0.10/ are spread over be1 and be2" \
  "kube-proxy's trick: -m statistic --mode random --probability 0.5 on the first DNAT rule, an unconditional one after it" t3
check 4 "the virtual IP works, but direct connections from the client to the backends on port 80 fail" \
  "In the FORWARD chain, conntrack knows which connections were DNATed: -m conntrack ! --ctstate DNAT" t4
finish_checks
