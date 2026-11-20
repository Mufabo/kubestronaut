#!/usr/bin/env bash
# Chapter 41 lab: two LANs joined by two routers, plus a host on "the
# internet". h1 has no default route, r1 does not forward and has no routes
# beyond its own networks, and nothing translates private addresses yet.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

netlab_fresh
nl_script <<'EOS'
host h1 srv inet
router r1 r2
wire h1 eth0 r1 eth0
wire r1 eth1 r2 eth0
wire r2 eth1 srv eth0
wire r2 eth2 inet eth0
addr h1  eth0 10.5.1.10/24
addr r1  eth0 10.5.1.1/24
addr r1  eth1 10.5.0.1/24
addr r2  eth0 10.5.0.2/24
addr r2  eth1 10.5.2.1/24
addr srv eth0 10.5.2.20/24
addr r2  eth2 198.51.100.2/24
addr inet eth0 198.51.100.1/24
# Routes that are already right:
route srv default via 10.5.2.1
route r2 10.5.1.0/24 via 10.5.0.1
route r2 default via 198.51.100.1
# The faults: r1 does not forward (yet), and h1 and r1 have no routes beyond
# their own subnets.
ip netns exec r1 sysctl -qw net.ipv4.ip_forward=0
web srv srv-web 80 0.0.0.0 "hello from srv (10.5.2.20)"
web inet inet-web 80 0.0.0.0 "hello from the internet (198.51.100.1)"
wait_port srv 80
wait_port inet 80
answers 41
topology <<'EOT'
Chapter 41 lab: two private LANs, two routers, and "the internet"

  office LAN 10.5.1.0/24    transit 10.5.0.0/24    server LAN 10.5.2.0/24
  h1 ----------------- r1 ------------------- r2 ------------------ srv
  .10            eth0  .1   eth1 .1      eth0 .2   eth1 .1            .20
                                                  |eth2 198.51.100.2
                                                  |   "the internet"
                                                  |   198.51.100.0/24
                                                 inet 198.51.100.1
  Web servers on port 80: srv and inet.
  inet only knows its own subnet: it has no routes to any 10.x network.
EOT
EOS
info "Lab ready. Open a shell in the lab with: make shell"
