#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require
nl_script <<'EOS'
# Task 1: h1 needs a default gateway
ip -n h1 route add default via 10.5.1.1
# Task 2: r1 must forward, and must know where 10.5.2.0/24 is
ip netns exec r1 sysctl -qw net.ipv4.ip_forward=1
ip -n r1 route add 10.5.2.0/24 via 10.5.0.2
# Task 3: r1 sends everything else to r2; r2 hides private sources behind its public address
ip -n r1 route add default via 10.5.0.2
ip netns exec r2 iptables -t nat -A POSTROUTING -o eth2 -j MASQUERADE
# Task 4: publish srv's web server on r2's public address, port 8080
ip netns exec r2 iptables -t nat -A PREROUTING -i eth2 -p tcp --dport 8080 -j DNAT --to-destination 10.5.2.20:80
EOS
