#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require

# The core router belongs to "another team": it must never learn Pod subnets.
core_untouched() { [[ "$(nl ip -n core route)" != *"10.9."* ]]; }
mtu_of() { nl ip -n "$1" -o link show dev "$2" 2>/dev/null | grep -o 'mtu [0-9]*' | cut -d' ' -f2; }

t1() { has_addr pod2a eth0 10.9.2.10/24 && can_ping pod2a 10.9.2.1; }
t2() { core_untouched && can_ping pod1a 10.9.2.10 && can_ping pod2a 10.9.1.10; }
t3() { core_untouched && can_ping pod1a 10.9.3.10 && can_ping pod3a 10.9.1.10; }
# 1422 bytes of data + 28 bytes of headers = a 1450-byte packet.
t4() {
  [[ "$(mtu_of pod1a eth0)" == 1450 && "$(mtu_of node1 veth-pod1a)" == 1450 &&
     "$(mtu_of pod3a eth0)" == 1450 && "$(mtu_of node3 veth-pod3a)" == 1450 ]] &&
    nl_ns pod1a ping -c1 -W2 -M "do" -s 1422 10.9.3.10 >/dev/null 2>&1
}

check 1 "pod2a has 10.9.2.10/24 on eth0 and can ping its gateway 10.9.2.1" \
  "Create a veth pair, put one end in pod2a as eth0 and the other in node2, attach that one to cni0, add the address and a default route" t1
check 2 "pod1a and pod2a can ping each other (core unchanged)" \
  "node1 and node2 are on the same LAN: each node needs a route to the other node's Pod subnet via the other node's address" t2
check 3 "pod1a and pod3a can ping each other (core still knows no Pod subnets)" \
  "core cannot route Pod addresses, so wrap them: a VXLAN device on node1 and node3 (ip link add vxlan0 type vxlan id ... remote ... dstport 4789 dev eth0) and routes through it" t3
check 4 "pod1a and pod3a use MTU 1450 on both ends of their veth pairs, and 1450-byte packets pass" \
  "VXLAN costs 50 bytes. Set the MTU on eth0 inside each Pod and on its veth end on the node: ip link set dev ... mtu 1450" t4
finish_checks
