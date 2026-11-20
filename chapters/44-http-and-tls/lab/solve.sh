#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require
nl_script <<'EOS'
cd /root/tls
# Task 1: ask the server for the other site by its Host header
ip netns exec client curl -s -H 'Host: api.lab.internal' http://10.0.8.80/ | awk '{print $NF}' > /root/answers/44/api-code
# Task 2: key + certificate signing request, then sign it with the lab CA
openssl req -newkey rsa:2048 -nodes -keyout web.key -out web.csr \
  -subj "/CN=web.lab.internal" -addext "subjectAltName=DNS:web.lab.internal" 2>/dev/null
openssl x509 -req -in web.csr -CA /root/ca/ca.crt -CAkey /root/ca/ca.key \
  -out web.crt -days 90 -copy_extensions copy 2>/dev/null
# Task 3: serve HTTPS with it
daemon web https labhttp --port 8443 --name web --cert /root/tls/web.crt --key /root/tls/web.key
wait_port web 8443
# Task 4: a client certificate from the same CA
openssl req -newkey rsa:2048 -nodes -keyout client.key -out client.csr -subj "/CN=client" 2>/dev/null
openssl x509 -req -in client.csr -CA /root/ca/ca.crt -CAkey /root/ca/ca.key -out client.crt -days 30 2>/dev/null
EOS
