#!/usr/bin/env bash
# Chapter 38 lab: a client and a server on one cable. The server's end of the
# cable is down, its web server listens on a port the reader must find, and a
# capture file holds a request for a secret page.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

# The secret page name is random per setup, so the answer cannot be copied.
mkdir -p "${here}/.state"
secret="page-$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6 || true)"
printf '%s\n' "$secret" > "${here}/.state/secret"

netlab_fresh
nl_script <<EOS
host client server
wire client eth0 server eth0
addr client eth0 10.0.2.10/24
addr server eth0 10.0.2.20/24
web server web 8080 10.0.2.20 "Welcome to the Chapter 38 server"
mkdir -p /srv/web/secret && echo "you found it" > /srv/web/secret/${secret}.html
wait_port server 8080
answers 38

# Record the mystery capture: a request for the secret page, captured on the
# client's side of the cable while the link is still up.
ip netns exec client tcpdump -i eth0 -n --immediate-mode -w ${LAB_ANSWERS}/mystery.pcap tcp port 8080 >/dev/null 2>&1 &
cap=\$!
sleep 1   # give tcpdump time to start listening
ip netns exec client curl -s --max-time 3 -o /dev/null http://10.0.2.20:8080/secret/${secret}.html
sleep 0.5
kill -INT \$cap; wait \$cap 2>/dev/null || true
tcpdump -n -r ${LAB_ANSWERS}/mystery.pcap 2>/dev/null | grep -q "GET /secret/" ||
  { echo "setup: the mystery capture came out empty; run make reset CH=38" >&2; exit 1; }

# Now break the cable at the server's end.
ip -n server link set eth0 down

topology <<'EOT'
Chapter 38 lab: one cable between two hosts

     client                                server
   10.0.2.10  eth0 ==================== eth0  10.0.2.20
                                         (web server on a TCP port
                                          you have to find)
EOT
EOS
info "Lab ready. Open a shell in the lab with: make shell"
