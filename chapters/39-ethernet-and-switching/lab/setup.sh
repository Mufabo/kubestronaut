#!/usr/bin/env bash
# Chapter 39 lab: four hosts on one switch. h3's switch port is not part of
# the switch, h2 has the wrong MTU, and the switch ports are numbered in a
# random order, so the reader has to read the switch's MAC table.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

# Random port numbers for h1, h2, h3, mystery.
read -r p1 p2 p3 p4 < <(shuf -e port1 port2 port3 port4 | xargs)
mkdir -p "${here}/.state"
printf '%s\n' "$p2" > "${here}/.state/h2-port"

netlab_fresh
nl_script <<EOS
switch sw1
host h1 h2 h3 mystery
plug h1 eth0 sw1 ${p1}
plug h2 eth0 sw1 ${p2}
plug h3 eth0 sw1 ${p3}
plug mystery eth0 sw1 ${p4}
ip -n sw1 link set ${p3} nomaster      # h3's cable reaches the switch, but the port is not part of it
ip -n h2 link set eth0 mtu 1400        # h2 disagrees with everyone else about the maximum frame size
addr h1 eth0 10.0.3.1/24
addr h2 eth0 10.0.3.2/24
addr h3 eth0 10.0.3.3/24
addr mystery eth0 10.0.3.99/24
answers 39
topology <<'EOT'
Chapter 39 lab: four hosts on one switch (sw1, bridge br0)

     h1            h2            h3          mystery
  10.0.3.1      10.0.3.2      10.0.3.3     10.0.3.99
     |eth0         |eth0         |eth0         |eth0
  +--+-------------+-------------+-------------+--+
  |  switch sw1: ports port1..port4 (which host   |
  |  is on which port? ask the switch)            |
  +-----------------------------------------------+
EOT
EOS
info "Lab ready. Open a shell in the lab with: make shell"
