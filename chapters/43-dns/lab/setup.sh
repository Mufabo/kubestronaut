#!/usr/bin/env bash
# Chapter 43 lab: a DNS server (dnsmasq) for the zone lab.internal, two web
# servers, and a client with no resolver configured. One record is missing,
# and one address has a random name only a reverse lookup reveals.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

mkdir -p "${here}/.state"
mystery="host-$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 5 || true).lab.internal"
printf '%s\n' "$mystery" > "${here}/.state/mystery"

netlab_fresh
nl_script <<EOS
switch lan
host client dns web api
for h in client dns web api; do plug "\$h" eth0 lan; done
addr client eth0 10.0.7.10/24
addr dns    eth0 10.0.7.53/24
addr web    eth0 10.0.7.80/24
addr api    eth0 10.0.7.81/24
web web web-http 80 0.0.0.0 "hello from web.lab.internal"
web api api-http 80 0.0.0.0 "hello from api.lab.internal"

# The zone's address records. dnsmasq rereads this file on SIGHUP.
mkdir -p /etc/dns
cat > /etc/dns/hosts.lab <<'EOT'
# Address records for lab.internal (format: address  name)
10.0.7.53   dns.lab.internal
10.0.7.80   web.lab.internal
10.0.7.99   ${mystery}
EOT
# Settings that need a restart to change.
cat > /etc/dns/dnsmasq.conf <<'EOT'
# Answer only from local data; never forward to another server.
no-resolv
no-hosts
addn-hosts=/etc/dns/hosts.lab
# Names under lab.internal that are not in the hosts file do not exist.
local=/lab.internal/
# Tell clients they may cache answers for 60 seconds.
local-ttl=60
listen-address=10.0.7.53
bind-interfaces
cname=www.lab.internal,web.lab.internal
txt-record=lab.internal,"Chapter 43 lab zone"
log-queries
log-facility=/var/log/netlab/dns-queries.log
EOT
daemon dns dns dnsmasq --keep-in-foreground --pid-file= --user=root --conf-file=/etc/dns/dnsmasq.conf
wait_port dns 53 udp
wait_port web 80
wait_port api 80
answers 43
topology <<'EOT'
Chapter 43 lab: one LAN, one DNS server for the zone lab.internal

    client          dns              web              api
  10.0.7.10     10.0.7.53        10.0.7.80        10.0.7.81
     |eth0         |eth0            |eth0            |eth0
  +--+-------------+----------------+----------------+--+
  |                   switch "lan"                     |
  +----------------------------------------------------+
  DNS server: dnsmasq on 10.0.7.53, data in /etc/dns/
  Web servers on port 80: web and api.
EOT
EOS
info "Lab ready. Open a shell in the lab with: make shell"
