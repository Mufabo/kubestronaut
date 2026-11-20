#!/usr/bin/env bash
# Chapter 42 lab: one server with four services. A TCP service on a random
# port, a UDP service on a random port, an app listening on localhost only,
# and a retired web service behind a firewall rule that drops connections.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

mkdir -p "${here}/.state"
tcp_port=$((20000 + RANDOM % 10000))
udp_port=$((40000 + RANDOM % 10000))
code="tcp-$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6 || true)"
printf '%s\n' "$udp_port" > "${here}/.state/udp-port"
printf '%s\n' "$code" > "${here}/.state/code"

netlab_fresh
nl_script <<EOS
host client server
wire client eth0 server eth0
addr client eth0 10.0.6.10/24
addr server eth0 10.0.6.20/24
# A TCP service that greets every connection with a code word.
daemon server greeter socat TCP-LISTEN:${tcp_port},fork,reuseaddr SYSTEM:"echo ${code}"
# A UDP service that answers every datagram with "pong".
daemon server pinger socat UDP4-RECVFROM:${udp_port},fork SYSTEM:"echo pong"
# An app that only listens on the loopback interface.
web server app 9090 127.0.0.1 "hello from app"
# A retired web service: still running, but a firewall rule drops its traffic.
web server old 8081 0.0.0.0 "hello from the old service"
ip netns exec server iptables -A INPUT -p tcp --dport 8081 -j DROP
wait_port server ${tcp_port}
wait_port server ${udp_port} udp
wait_port server 9090
wait_port server 8081
answers 42
topology <<'EOT'
Chapter 42 lab: a client and a busy server

     client                                   server
   10.0.6.10  eth0 ======================= eth0  10.0.6.20
                                  services: a TCP greeter (port ?)
                                            a UDP pinger  (port ?)
                                            an app on 9090
                                            an old web service on 8081
EOT
EOS
info "Lab ready. Open a shell in the lab with: make shell"
