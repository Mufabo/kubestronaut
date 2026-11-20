#!/usr/bin/env bash
# Chapter 45 lab: three "nodes" with a bridge each, the way a simple CNI
# plugin wires Pods. node1 and node2 share a LAN; node3 sits behind a core
# router that only knows node addresses, never Pod addresses.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

netlab_fresh
nl_script <<'EOS'
# The node network ("underlay"): node1 and node2 on one LAN, node3 behind core.
switch lan9
router core node1 node2 node3
plug core  eth0 lan9
plug node1 eth0 lan9
plug node2 eth0 lan9
wire core eth1 node3 eth0
addr core  eth0 192.168.9.1/24
addr core  eth1 192.168.10.1/24
addr node1 eth0 192.168.9.11/24
addr node2 eth0 192.168.9.12/24
addr node3 eth0 192.168.10.13/24
for n in node1 node2; do route "$n" default via 192.168.9.1; done
route node3 default via 192.168.10.1

# Each node gets a bridge, cni0, holding the first address of its Pod subnet.
pod_subnet() { case $1 in node1) echo 1 ;; node2) echo 2 ;; node3) echo 3 ;; esac; }
for n in node1 node2 node3; do
  i="$(pod_subnet "$n")"
  ip -n "$n" link add cni0 type bridge
  ip -n "$n" link set cni0 up
  addr "$n" cni0 "10.9.${i}.1/24"
done

# A Pod: a namespace whose eth0 is one end of a veth pair; the other end is
# attached to the node's cni0 bridge.
pod() {
  local p=$1 n=$2 ip=$3 i
  i="$(pod_subnet "$n")"
  host "$p"
  wire "$p" eth0 "$n" "veth-${p}"
  ip -n "$n" link set "veth-${p}" master cni0
  addr "$p" eth0 "${ip}/24"
  route "$p" default via "10.9.${i}.1"
}
pod pod1a node1 10.9.1.10
pod pod3a node3 10.9.3.10
host pod2a        # exists, but nothing is wired yet

answers 45
topology <<'EOT'
Chapter 45 lab: a Pod network built by hand

   pod1a 10.9.1.10      pod2a (unwired)          pod3a 10.9.3.10
        |                    .                        |
  [cni0 10.9.1.1]      [cni0 10.9.2.1]          [cni0 10.9.3.1]
     node1                node2                    node3
  192.168.9.11         192.168.9.12            192.168.10.13
     |eth0                |eth0                    |eth0
  +--+--------------------+--+                     |
  |   switch lan9 192.168.9.0/24  |               |
  +-------------+-----------------+               |
                |eth0 192.168.9.1      eth1 192.168.10.1
                +------------- core ---------------+
  Pod subnets: node1 10.9.1.0/24, node2 10.9.2.0/24, node3 10.9.3.0/24
  core belongs to "another team": it knows node addresses only.
EOT
EOS
info "Lab ready. Open a shell in the lab with: make shell"
