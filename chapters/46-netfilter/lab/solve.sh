#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require
nl_script <<'EOS'
in_node() { ip netns exec node "$@"; }
# Task 1: the nftables table that drops ping
in_node nft delete table inet guard
# Tasks 2 and 3: a kube-proxy-style virtual IP, split 50/50 between the backends
in_node iptables -t nat -N VIP-WEB
in_node iptables -t nat -A PREROUTING -d 10.96.0.10/32 -p tcp --dport 80 -j VIP-WEB
in_node iptables -t nat -A VIP-WEB -p tcp -m statistic --mode random --probability 0.5 -j DNAT --to-destination 10.10.2.11:80
in_node iptables -t nat -A VIP-WEB -p tcp -j DNAT --to-destination 10.10.2.12:80
# Task 4: only DNATed connections may reach the backends' port 80
in_node iptables -A FORWARD -d 10.10.2.0/24 -p tcp --dport 80 -m conntrack ! --ctstate DNAT -j REJECT --reject-with tcp-reset
EOS
