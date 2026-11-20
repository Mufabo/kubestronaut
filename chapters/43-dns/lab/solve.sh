#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require
nl_script <<'EOS'
# Tasks 1 and 3: the client's resolver, with a search domain
printf 'nameserver 10.0.7.53\nsearch lab.internal\n' > /etc/netns/client/resolv.conf
# Task 2: add the record and tell dnsmasq to reread its hosts file
echo '10.0.7.81   api.lab.internal' >> /etc/dns/hosts.lab
pkill -HUP dnsmasq
# Task 4: reverse lookup
ip netns exec client dig +short -x 10.0.7.99 | sed 's/\.$//' > /root/answers/43/mystery-name
EOS
