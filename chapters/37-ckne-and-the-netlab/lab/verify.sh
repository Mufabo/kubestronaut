#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require

t1() { answer_is "${LAB_ANSWERS}/beta-ip" 10.0.1.2; }
t2() { ns_exists hello; }
t3() { link_up gamma eth0 && can_ping gamma 10.0.1.1; }

check 1 "beta's address is in ${LAB_ANSWERS}/beta-ip" \
  "Run netmap inside the lab shell, then: echo <address> > ${LAB_ANSWERS}/beta-ip (the address without /24)" t1
check 2 "a network namespace named hello exists" \
  "ip netns add creates one; ip netns list shows them" t2
check 3 "gamma's eth0 is up and gamma can ping alpha" \
  "Run the command inside gamma: on gamma ip link set eth0 up" t3
finish_checks
