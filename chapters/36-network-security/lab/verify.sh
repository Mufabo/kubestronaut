#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

k() { kubectl -n "$LAB_NS" "$@"; }
jp() { k get "$1" -o "jsonpath=$2" 2>/dev/null; }

# fetch <from-pod> <url>: what the Pod gets back. Sets FETCH_OUT, returns the status.
fetch() {
  FETCH_OUT="$(k exec "$1" -- wget -q -T 3 -O- "$2" 2>&1)"
}
# reachable <from-pod> <url>: the request is answered with "ok"
reachable() { fetch "$1" "$2" && [[ "$FETCH_OUT" == *ok* ]]; }
# blocked <from-pod> <url>: the request times out, as a policy drop does. A DNS failure
# is not a block, so it does not count.
blocked() { ! fetch "$1" "$2" && [[ "$FETCH_OUT" == *"timed out"* ]]; }
# resolves <from-pod> <name>: the Pod's DNS returns an answer for the name
resolves() { [[ "$(k exec "$1" -- nslookup "$2" 2>&1)" == *"Name:"* ]]; }

t1() {
  [[ "$(jp networkpolicy/default-deny '{.spec.podSelector}')" == '{}' ]] &&
  [[ "$(jp networkpolicy/default-deny '{.spec.policyTypes}')" == '["Ingress","Egress"]' ]] &&
  [[ "$(jp networkpolicy/allow-dns '{.spec.policyTypes}')" == '["Egress"]' ]] &&
  [[ "$(jp networkpolicy/allow-dns '{.spec.egress[0].ports[*].port}')" == "53 53" ]] &&
  blocked stranger http://api:8080/ &&
  resolves stranger api
}

t2() {
  [[ "$(jp networkpolicy/frontend-to-api '{.spec.podSelector.matchLabels.app}')" == frontend ]] &&
  [[ "$(jp networkpolicy/frontend-to-api '{.spec.egress[0].to[0].podSelector.matchLabels.app}')" == api ]] &&
  [[ "$(jp networkpolicy/frontend-to-api '{.spec.egress[0].ports[0].port}')" == 8080 ]] &&
  [[ "$(jp networkpolicy/api-from-frontend '{.spec.podSelector.matchLabels.app}')" == api ]] &&
  [[ "$(jp networkpolicy/api-from-frontend '{.spec.ingress[0].from[0].podSelector.matchLabels.app}')" == frontend ]] &&
  [[ "$(jp networkpolicy/api-from-frontend '{.spec.ingress[0].ports[0].port}')" == 8080 ]] &&
  reachable frontend http://api:8080/ && blocked stranger http://api:8080/
}

t3() {
  [[ "$(jp networkpolicy/api-to-db '{.spec.podSelector.matchLabels.app}')" == api ]] &&
  [[ "$(jp networkpolicy/api-to-db '{.spec.egress[0].to[0].podSelector.matchLabels.app}')" == db ]] &&
  [[ "$(jp networkpolicy/api-to-db '{.spec.egress[0].ports[0].port}')" == 5432 ]] &&
  [[ "$(jp networkpolicy/db-from-api '{.spec.podSelector.matchLabels.app}')" == db ]] &&
  [[ "$(jp networkpolicy/db-from-api '{.spec.ingress[0].from[0].podSelector.matchLabels.app}')" == api ]] &&
  [[ "$(jp networkpolicy/db-from-api '{.spec.ingress[0].ports[0].port}')" == 5432 ]] &&
  reachable api http://db:5432/ && blocked frontend http://db:5432/
}

t4() {
  [[ "$(jp secret/api-tls '{.type}')" == kubernetes.io/tls ]] || return 1
  [[ -s "$LAB_CERT" && -s "$LAB_KEY" ]] || return 1
  [[ "$(jp secret/api-tls '{.data.tls\.crt}' | base64 -d)" == "$(cat "$LAB_CERT")" ]] &&
  [[ "$(jp secret/api-tls '{.data.tls\.key}' | base64 -d)" == "$(cat "$LAB_KEY")" ]]
}

check 1 "A default deny for ingress and egress, with DNS allowed, blocks the stranger from the api, and DNS still resolves" \
  "networkpolicy default-deny: empty podSelector, policyTypes Ingress and Egress; allow-dns: egress to port 53, UDP and TCP" t1
check 2 "The frontend reaches the api on port 8080, and the stranger does not" \
  "both ends need a policy: an egress rule on the frontend and an ingress rule on the api" t2
check 3 "The api reaches the db on port 5432, and the frontend does not" \
  "both ends need a policy: an egress rule on the api and an ingress rule on the db" t3
check 4 "Secret api-tls is a TLS Secret holding the certificate and key in ${LAB_CERT_DIR}" \
  "kubectl create secret tls api-tls --cert=... --key=... in the lab Namespace" t4

finish_checks
