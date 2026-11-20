#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require
code="$(cat "${here}/.state/code" 2>/dev/null || true)"

# fingerprint <file>   SHA-256 fingerprint of a certificate file in the container
fingerprint() { nl openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null; }

t1() { [[ -n "$code" ]] && answer_is "${LAB_ANSWERS}/api-code" "$code"; }
t2() {
  local san keymod certmod
  [[ "$(nl openssl verify -CAfile /root/ca/ca.crt /root/tls/web.crt 2>/dev/null)" == *": OK" ]] || return 1
  san="$(nl openssl x509 -in /root/tls/web.crt -noout -ext subjectAltName 2>/dev/null)"
  [[ "$san" == *"DNS:web.lab.internal"* ]] || return 1
  keymod="$(nl openssl pkey -in /root/tls/web.key -pubout 2>/dev/null)"
  certmod="$(nl openssl x509 -in /root/tls/web.crt -noout -pubkey 2>/dev/null)"
  [[ -n "$keymod" && "$keymod" == "$certmod" ]]
}
t3() {
  local served mine
  http_says client https://web.lab.internal:8443/ "hello from" --cacert /root/ca/ca.crt || return 1
  served="$(nl_ns client sh -c 'openssl s_client -connect web.lab.internal:8443 -servername web.lab.internal </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256' 2>/dev/null)"
  mine="$(fingerprint /root/tls/web.crt)"
  [[ -n "$mine" && "$served" == "$mine" ]]
}
t4() {
  [[ "$(nl openssl x509 -in /root/tls/client.crt -noout -subject 2>/dev/null)" == *"CN=client"* ]] &&
    http_says client https://web.lab.internal:9443/ "client certificate: client" \
      --cacert /root/ca/ca.crt --cert /root/tls/client.crt --key /root/tls/client.key
}

check 1 "the code from the api.lab.internal site is in ${LAB_ANSWERS}/api-code" \
  "The server picks the site by the Host header. curl -H 'Host: ...' or curl --resolve" t1
check 2 "/root/tls/web.crt is signed by the lab CA, names web.lab.internal, and matches /root/tls/web.key" \
  "openssl req -newkey ... -addext subjectAltName=DNS:web.lab.internal, then openssl x509 -req ... -CA /root/ca/ca.crt -copy_extensions copy" t2
check 3 "web serves HTTPS on port 8443 with your certificate, trusted via the lab CA" \
  "on web nohup labhttp --port 8443 --name web --cert /root/tls/web.crt --key /root/tls/web.key > /tmp/https.log 2>&1 &" t3
check 4 "with /root/tls/client.crt (CN=client) the client gets through the mutual-TLS service on 9443" \
  "Issue a client certificate from the same CA with the subject /CN=client, then curl --cert ... --key ..." t4
finish_checks
