#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require
nl_script <<'EOS'
# Task 1: 150 = 10010110; a /27 keeps the first 3 bits of the 4th octet: 100 00000 = 128
echo 172.20.13.128 > /root/answers/40/network
echo 172.20.13.159 > /root/answers/40/broadcast
echo 30 > /root/answers/40/hosts
# Task 2
ip -n newbie addr add 10.0.4.30/24 dev eth0
# Task 3
ip -n c addr del 10.0.4.200/25 dev eth0
ip -n c addr add 10.0.4.200/24 dev eth0
# Task 4 (new IPv6 addresses need a moment before they can be used)
ip -n a addr add fd00:4::a/64 dev eth0
ip -n b addr add fd00:4::b/64 dev eth0
for i in $(seq 1 20); do
  ip netns exec a ping -6 -c1 -W1 fd00:4::b >/dev/null 2>&1 && break
  sleep 0.5
done
EOS
