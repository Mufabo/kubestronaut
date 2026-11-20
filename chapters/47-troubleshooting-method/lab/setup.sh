#!/usr/bin/env bash
# Chapter 47 lab: an office and a small data centre, with one fault planted
# at each layer between a laptop and the web app it needs.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

netlab_fresh
nl_script <<'EOS'
host laptop dns app
router r1
switch dc
wire laptop eth0 r1 eth0
plug r1 eth1 dc
plug dns eth0 dc
plug app eth0 dc
addr laptop eth0 10.11.1.10/24
addr r1 eth0 10.11.1.1/24
addr r1 eth1 10.11.2.1/24
addr dns eth0 10.11.2.53/24
addr app eth0 10.11.2.80/24
route laptop default via 10.11.1.1
route dns default via 10.11.2.1
printf 'nameserver 10.11.2.53\nsearch corp.internal\n' > /etc/netns/laptop/resolv.conf

# DNS for corp.internal (dnsmasq, as in Chapter 43).
mkdir -p /etc/dns
cat > /etc/dns/hosts.corp <<'EOT'
10.11.2.53   dns.corp.internal
10.11.2.81   app.corp.internal
EOT
cat > /etc/dns/dnsmasq.conf <<'EOT'
no-resolv
no-hosts
addn-hosts=/etc/dns/hosts.corp
local=/corp.internal/
local-ttl=5
listen-address=10.11.2.53
bind-interfaces
log-queries
log-facility=/var/log/netlab/dns-queries.log
EOT
daemon dns dns dnsmasq --keep-in-foreground --pid-file= --user=root --conf-file=/etc/dns/dnsmasq.conf
# The app: a web server on port 8080.
mkdir -p /srv/app
web app app 8080 127.0.0.1 "hello from app"
wait_port dns 53 udp
wait_port app 8080

# The faults, bottom to top:
ip -n dc link set dns-eth0 nomaster                                   # layer 2: dns's switch port is not on the switch
ip netns exec r1 iptables -A FORWARD -p tcp --dport 8080 -j DROP      # layer 4: a firewall rule on r1
# Layer 3: app has no default route (left out above). Layer 7: the DNS
# record for app points to .81. Layer 4: app listens on 127.0.0.1 only.

answers 47
topology <<'EOT'
Chapter 47 lab: an office laptop and a small data centre

   laptop 10.11.1.10 ---eth0--- r1 ---eth1--- switch "dc"
   (resolver: 10.11.2.53,  10.11.1.1   10.11.2.1   |       |
    search corp.internal)                         dns     app
                                            10.11.2.53  10.11.2.80
                                             (dnsmasq)  (web :8080)
   Goal: on the laptop, curl http://app.corp.internal:8080/ works.
   DNS data: /etc/dns/hosts.corp (reload: pkill -HUP dnsmasq)
   The app: python3 -m http.server 8080 --directory /srv/app
EOT
EOS
info "Lab ready. Open a shell in the lab with: make shell"
