#!/usr/bin/env bash
# Chapter 44 lab: a web server with two virtual hosts, a lab certificate
# authority, and an HTTPS service that demands client certificates.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

mkdir -p "${here}/.state"
code="api-$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6 || true)"
printf '%s\n' "$code" > "${here}/.state/code"

netlab_fresh
nl_script <<EOS
host client web
wire client eth0 web eth0
addr client eth0 10.0.8.10/24
addr web eth0 10.0.8.80/24
# The client knows web.lab.internal from its hosts file (Chapter 43 did DNS).
printf '10.0.8.80\tweb.lab.internal\n' >> /etc/netns/client/hosts

# The lab's certificate authority.
mkdir -p /root/ca /root/tls /srv/tls
openssl req -x509 -newkey rsa:2048 -nodes -keyout /root/ca/ca.key -out /root/ca/ca.crt \
  -days 365 -subj "/CN=Lab CA" 2>/dev/null
# The mutual-TLS service's own certificate.
openssl req -newkey rsa:2048 -nodes -keyout /srv/tls/mtls.key -out /srv/tls/mtls.csr \
  -subj "/CN=web.lab.internal" -addext "subjectAltName=DNS:web.lab.internal" 2>/dev/null
openssl x509 -req -in /srv/tls/mtls.csr -CA /root/ca/ca.crt -CAkey /root/ca/ca.key \
  -out /srv/tls/mtls.crt -days 90 -copy_extensions copy 2>/dev/null

daemon web http labhttp --port 80 --name web --vhost "api.lab.internal=hello from the api site, code ${code}"
daemon web mtls labhttp --port 9443 --name web-mtls --cert /srv/tls/mtls.crt --key /srv/tls/mtls.key --client-ca /root/ca/ca.crt
wait_port web 80
wait_port web 9443
answers 44
topology <<'EOT'
Chapter 44 lab: a client and a web server

     client                                   web
   10.0.8.10  eth0 ======================= eth0  10.0.8.80
                                   http  :80    sites web.lab.internal
                                                and api.lab.internal
                                   https :8443  (yours to start)
                                   https :9443  requires a client certificate
  Lab CA: /root/ca/ca.crt and /root/ca/ca.key
  Server program: labhttp (labhttp --help)
EOT
EOS
info "Lab ready. Open a shell in the lab with: make shell"
