#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require
mystery="$(cat "${here}/.state/mystery" 2>/dev/null || true)"

# dig always asks a DNS server (never /etc/hosts), so these test real DNS.
lookup() { nl_ns client dig +short +time=2 +tries=1 "$@" 2>/dev/null | tail -n 1; }

t1() { [[ "$(lookup web.lab.internal)" == 10.0.7.80 ]]; }
t2() {
  [[ "$(lookup @10.0.7.53 api.lab.internal)" == 10.0.7.81 ]] &&
    [[ "$(lookup @10.0.7.53 web.lab.internal)" == 10.0.7.80 ]]
}
t3() { [[ "$(lookup +search web)" == 10.0.7.80 ]] && http_says client http://web/ "hello from web"; }
t4() { [[ -n "$mystery" ]] && answer_is "${LAB_ANSWERS}/mystery-name" "$mystery"; }

check 1 "the client resolves web.lab.internal through the DNS server" \
  "The client's resolver configuration is /etc/resolv.conf, and for a namespace that file is /etc/netns/<name>/resolv.conf" t1
check 2 "the DNS server answers api.lab.internal with 10.0.7.81 (and still knows web)" \
  "Add the record to /etc/dns/hosts.lab, then make dnsmasq reread it: pkill -HUP dnsmasq" t2
check 3 "the client resolves the short name web, and curl http://web/ works" \
  "A search domain in the client's resolv.conf lets short names be completed" t3
check 4 "the name of 10.0.7.99 is in ${LAB_ANSWERS}/mystery-name" \
  "A reverse lookup: dig -x 10.0.7.99" t4
finish_checks
