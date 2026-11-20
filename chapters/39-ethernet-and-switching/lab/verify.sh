#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require
h2port="$(cat "${here}/.state/h2-port" 2>/dev/null || true)"

addresses_unchanged() {
  has_addr h1 eth0 10.0.3.1/24 && has_addr h2 eth0 10.0.3.2/24 &&
    has_addr h3 eth0 10.0.3.3/24 && has_addr mystery eth0 10.0.3.99/24
}
t1() { addresses_unchanged && can_ping h3 10.0.3.1; }
t2() { [[ -n "$h2port" ]] && answer_is "${LAB_ANSWERS}/h2-port" "$h2port"; }
t3() {
  local mac
  mac="$(nl ip -n mystery -br link show dev eth0 | awk '{print $3}')"
  [[ -n "$mac" ]] && answer_is "${LAB_ANSWERS}/mac-99" "$mac"
}
# 1472 bytes of ping data + 8 (ICMP header) + 20 (IP header) = a 1500-byte packet.
t4() {
  nl_ns h1 ping -c1 -W2 -M "do" -s 1472 10.0.3.2 >/dev/null 2>&1 &&
    nl_ns h2 ping -c1 -W2 -M "do" -s 1472 10.0.3.1 >/dev/null 2>&1
}

check 1 "h3 can ping h1 (addresses unchanged)" \
  "Which switch port does h3's cable reach, and is that port part of br0? Compare ip -n sw1 link with bridge -n sw1 link" t1
check 2 "the switch port h2 is connected to is in ${LAB_ANSWERS}/h2-port" \
  "Make h2 send something, then read the switch's MAC table: bridge -n sw1 fdb show br br0" t2
check 3 "the MAC address of 10.0.3.99 is in ${LAB_ANSWERS}/mac-99" \
  "Ping 10.0.3.99 from any host, then look at that host's ARP cache: ip neigh" t3
check 4 "1500-byte packets pass between h1 and h2 in both directions without fragmenting" \
  "Compare the mtu value in ip link show dev eth0 on each host" t4
finish_checks
