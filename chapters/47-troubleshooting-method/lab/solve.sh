#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require
nl_script <<'EOS'
# Task 1 (layer 2): put dns's port back on the switch
ip -n dc link set dns-eth0 master br0
# Task 2 (layer 7): fix the record and reload dnsmasq
sed -i 's/^10\.11\.2\.81 /10.11.2.80 /' /etc/dns/hosts.corp
pkill -HUP dnsmasq
# Task 3 (layer 3): app needs a way back
ip -n app route add default via 10.11.2.1
# Task 4 (layer 4, filter): remove the DROP rule on r1
ip netns exec r1 iptables -D FORWARD -p tcp --dport 8080 -j DROP
# Task 5 (layer 4, listener): restart the app on all addresses
web app app 8080 0.0.0.0 "hello from app"
wait_port app 8080
EOS
