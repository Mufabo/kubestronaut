#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require
nl_script <<'EOS'
# Task 1: h3's port is the one switch port without "master br0"
port="$(ip -n sw1 -o link show | awk -F': ' '/port/ && !/master br0/ {print $2}' | cut -d@ -f1)"
ip -n sw1 link set "$port" master br0
# Task 2: make h2 talk, then find its MAC in the switch's table
ip netns exec h2 ping -c1 -W2 10.0.3.1 >/dev/null
mac="$(ip -n h2 -br link show dev eth0 | awk '{print $3}')"
bridge -n sw1 fdb show br br0 | awk -v m="$mac" '$1 == m {print $3}' > /root/answers/39/h2-port
# Task 3: ARP for 10.0.3.99, then read the neighbour table
ip netns exec h1 ping -c1 -W2 10.0.3.99 >/dev/null
ip -n h1 neigh show 10.0.3.99 | awk '{print $5}' > /root/answers/39/mac-99
# Task 4: h2 is the only host with MTU 1400
ip -n h2 link set eth0 mtu 1500
EOS
