#!/usr/bin/env bash
# Chapter 37 lab: three hosts on one switch. Gets the reader through the
# lab loop (make lab / shell / check / reset) before any networking theory.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

netlab_fresh
nl_script <<'EOS'
switch lan
host alpha beta gamma
plug alpha eth0 lan
plug beta  eth0 lan
plug gamma eth0 lan gamma-eth0 down
ip -n lan link set gamma-eth0 up      # the switch end is up; gamma's end stays down
addr alpha eth0 10.0.1.1/24
addr beta  eth0 10.0.1.2/24
addr gamma eth0 10.0.1.3/24
answers 37
topology <<'EOT'
Chapter 37 lab: three hosts plugged into one switch

        alpha             beta              gamma
     10.0.1.1          10.0.1.2          10.0.1.3
        |eth0             |eth0             |eth0 (DOWN)
   +----+-----------------+-----------------+----+
   |                  switch "lan"               |
   +---------------------------------------------+
EOT
EOS
info "Lab ready. Open a shell in the lab with: make shell"
