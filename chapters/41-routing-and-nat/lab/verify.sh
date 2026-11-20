#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require

# "The internet" must not learn about private networks: NAT has to do the work.
inet_untouched() { [[ "$(nl ip -n inet route)" != *"10."* ]]; }

t1() { can_ping h1 10.5.0.1; }
t2() { http_says h1 http://10.5.2.20/ "hello from srv"; }
t3() {
  inet_untouched &&
    http_says h1 http://198.51.100.1/ "hello from the internet" &&
    http_says srv http://198.51.100.1/ "hello from the internet"
}
t4() { inet_untouched && http_says inet http://198.51.100.2:8080/ "hello from srv"; }

check 1 "h1 can ping r1's far interface (10.5.0.1)" \
  "h1 only knows its own subnet. Where should it send everything else? (ip route add default via ...)" t1
check 2 "h1 can fetch http://10.5.2.20/ from srv" \
  "Follow the packet: does r1 forward at all (sysctl net.ipv4.ip_forward), and does it know where 10.5.2.0/24 is? traceroute -n helps" t2
check 3 "h1 and srv can fetch http://198.51.100.1/ (no routes added on inet)" \
  "Capture on inet: what source address arrives, and can inet answer it? The edge router must translate (iptables -t nat ... MASQUERADE)" t3
check 4 "inet gets srv's page from http://198.51.100.2:8080/ (no routes added on inet)" \
  "Forward a port on r2: iptables -t nat ... PREROUTING ... DNAT --to-destination 10.5.2.20:80" t4
finish_checks
