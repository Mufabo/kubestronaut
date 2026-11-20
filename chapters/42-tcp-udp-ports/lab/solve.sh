#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require
nl_script <<'EOS'
# Task 1: the TCP port that is neither 9090 nor 8081 belongs to the greeter
port="$(ip netns exec server ss -Hltn | awk '{print $4}' | grep -v ':9090$' | grep -v ':8081$' | cut -d: -f2)"
ip netns exec client nc -w 2 10.0.6.20 "$port" < /dev/null > /root/answers/42/greeting
# Task 2
ip netns exec server ss -Hlun | awk '{print $4}' | cut -d: -f2 > /root/answers/42/udp-port
# Task 3: restart the app on all addresses (topo.sh's web stops the old one first)
web server app 9090 0.0.0.0 "hello from app"
wait_port server 9090
# Task 4: answer with a TCP reset instead of dropping
ip netns exec server iptables -R INPUT 1 -p tcp --dport 8081 -j REJECT --reject-with tcp-reset
EOS
