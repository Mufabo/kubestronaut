#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require

t1() {
  answer_is "${LAB_ANSWERS}/network" 172.20.13.128 &&
    answer_is "${LAB_ANSWERS}/broadcast" 172.20.13.159 &&
    answer_is "${LAB_ANSWERS}/hosts" 30
}
t2() { has_addr newbie eth0 10.0.4.30/24 && can_ping newbie 10.0.4.10 && can_ping newbie 10.0.4.20; }
t3() {
  has_addr c eth0 10.0.4.200/24 && ! has_addr c eth0 10.0.4.200/25 &&
    can_ping c 10.0.4.10 && can_ping a 10.0.4.200
}
t4() {
  has_addr a eth0 fd00:4::a/64 && has_addr b eth0 fd00:4::b/64 &&
    nl_ns a ping -6 -c1 -W2 fd00:4::b >/dev/null 2>&1
}

check 1 "network, broadcast, and host count for 172.20.13.150/27 are in ${LAB_ANSWERS}/" \
  "Write the 4th octet in binary and keep the first 3 bits; check yourself with ipcalc 172.20.13.150/27" t1
check 2 "newbie has 10.0.4.30/24 and can ping a and b" \
  "Use the same prefix length as a and b: on newbie ip address add ..." t2
check 3 "c keeps 10.0.4.200, with the LAN's prefix length, and can talk to a" \
  "Compare on c ip route with on a ip route. Delete the wrong address and add the right one" t3
check 4 "a has fd00:4::a/64, b has fd00:4::b/64, and a can ping b over IPv6" \
  "ip address add works for IPv6 too; test with on a ping -6 fd00:4::b" t4
finish_checks
