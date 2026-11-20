#!/usr/bin/env bash
# Chapter 46 lab: a client, a "node" that routes and filters, and two backend
# web servers. The reader builds a kube-proxy-style virtual IP with DNAT. An
# nftables table on the node blocks ping from the client.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

netlab_fresh
nl_script <<'EOS'
host client be1 be2
router node
switch backends
wire client eth0 node eth0
plug node eth1 backends
plug be1 eth0 backends
plug be2 eth0 backends
addr client eth0 10.10.1.10/24
addr node   eth0 10.10.1.1/24
addr node   eth1 10.10.2.1/24
addr be1    eth0 10.10.2.11/24
addr be2    eth0 10.10.2.12/24
route client default via 10.10.1.1
route be1 default via 10.10.2.1
route be2 default via 10.10.2.1
web be1 be1-http 80 0.0.0.0 "hello from be1 (10.10.2.11)"
web be2 be2-http 80 0.0.0.0 "hello from be2 (10.10.2.12)"
# Someone's forgotten experiment: an nftables table that drops ping.
ip netns exec node nft -f - <<'EOT'
table inet guard {
  chain input {
    type filter hook input priority 0; policy accept;
    ip saddr 10.10.1.0/24 icmp type echo-request counter drop comment "testing, remove later"
  }
}
EOT
wait_port be1 80
wait_port be2 80
answers 46
topology <<'EOT'
Chapter 46 lab: a node in front of two backends

  client 10.10.1.10 ---eth0--- node ---eth1--- switch "backends"
                       10.10.1.1    10.10.2.1     |          |
                                                 be1        be2
                                             10.10.2.11  10.10.2.12
                                              (web :80)   (web :80)
  Virtual IP to build on the node: 10.96.0.10, port 80
  (no host has this address; the client's default route points to node)
EOT
EOS
info "Lab ready. Open a shell in the lab with: make shell"
