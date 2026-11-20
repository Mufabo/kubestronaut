#!/usr/bin/env bash
# Chapter 40 lab: one LAN, 10.0.4.0/24. A new host has no address, one host
# has the wrong prefix length, and IPv6 is switched on (but unconfigured).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

netlab_fresh
nl_script <<'EOS'
export NETLAB_IPV6=1          # this chapter introduces IPv6
switch lan
host a b c newbie
for h in a b c newbie; do plug "$h" eth0 lan; done
addr a eth0 10.0.4.10/24
addr b eth0 10.0.4.20/24
addr c eth0 10.0.4.200/25     # wrong prefix length: c thinks its network is 10.0.4.128/25
answers 40
topology <<'EOT'
Chapter 40 lab: one LAN, intended to be 10.0.4.0/24

       a                b                c              newbie
  10.0.4.10/24     10.0.4.20/24    10.0.4.200/25     (no address)
       |eth0            |eth0           |eth0            |eth0
  +----+----------------+---------------+----------------+----+
  |                       switch "lan"                        |
  +-----------------------------------------------------------+
EOT
EOS
info "Lab ready. Open a shell in the lab with: make shell"
