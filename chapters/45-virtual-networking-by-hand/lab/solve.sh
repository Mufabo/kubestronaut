#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require
nl_script <<'EOS'
# Task 1: wire pod2a into node2's bridge
ip link add veth-pod2a type veth peer name eth0 netns pod2a
ip link set veth-pod2a netns node2
ip -n node2 link set veth-pod2a master cni0
ip -n node2 link set veth-pod2a up
ip -n pod2a addr add 10.9.2.10/24 dev eth0
ip -n pod2a link set eth0 up
ip -n pod2a route add default via 10.9.2.1
# Task 2: routed mode between nodes on the same LAN
ip -n node1 route add 10.9.2.0/24 via 192.168.9.12
ip -n node2 route add 10.9.1.0/24 via 192.168.9.11
# Task 3: a VXLAN tunnel between node1 and node3, and routes through it
ip -n node1 link add vxlan0 type vxlan id 42 local 192.168.9.11 remote 192.168.10.13 dstport 4789 dev eth0
ip -n node3 link add vxlan0 type vxlan id 42 local 192.168.10.13 remote 192.168.9.11 dstport 4789 dev eth0
ip -n node1 addr add 10.9.255.1/30 dev vxlan0
ip -n node3 addr add 10.9.255.2/30 dev vxlan0
ip -n node1 link set vxlan0 up
ip -n node3 link set vxlan0 up
ip -n node1 route add 10.9.3.0/24 via 10.9.255.2
ip -n node3 route add 10.9.1.0/24 via 10.9.255.1
# Task 4: Pod interfaces that fit inside the tunnel
for pair in pod1a:node1 pod3a:node3; do
  p=${pair%%:*}; n=${pair##*:}
  ip -n "$p" link set dev eth0 mtu 1450
  ip -n "$n" link set dev "veth-${p}" mtu 1450
done
EOS
