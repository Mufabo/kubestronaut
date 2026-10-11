#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

k() { kubectl -n "$LAB_NS" "$@"; }
# jp <resource> <jsonpath>
jp() { k get "$1" -o "jsonpath=$2" 2>/dev/null; }

t1() {
  [[ "$(jp ingress/shop '{.spec.ingressClassName}')" == nginx ]] &&
  [[ "$(jp ingress/shop '{.spec.rules[*].host}')" == shop.example.test ]] &&
  [[ "$(jp ingress/shop '{.spec.rules[0].http.paths[0].path}')" == / ]] &&
  [[ "$(jp ingress/shop '{.spec.rules[0].http.paths[0].pathType}')" == Prefix ]] &&
  [[ "$(jp ingress/shop '{.spec.rules[0].http.paths[0].backend.service.name}')" == shop ]] &&
  [[ "$(jp ingress/shop '{.spec.rules[0].http.paths[0].backend.service.port.number}')" == 80 ]]
}

t2() {
  [[ "$(jp secret/docs-tls '{.type}')" == kubernetes.io/tls ]] &&
  [[ "$(jp ingress/docs '{.spec.ingressClassName}')" == nginx ]] &&
  [[ "$(jp ingress/docs '{.spec.tls[0].hosts[0]}')" == docs.example.test ]] &&
  [[ "$(jp ingress/docs '{.spec.tls[0].secretName}')" == docs-tls ]] &&
  [[ "$(jp ingress/docs '{.spec.rules[0].host}')" == docs.example.test ]] &&
  [[ "$(jp ingress/docs '{.spec.rules[0].http.paths[0].path}')" == /docs ]] &&
  [[ "$(jp ingress/docs '{.spec.rules[0].http.paths[0].pathType}')" == Prefix ]] &&
  [[ "$(jp ingress/docs '{.spec.rules[0].http.paths[0].backend.service.name}')" == docs ]] &&
  [[ "$(jp ingress/docs '{.spec.rules[0].http.paths[0].backend.service.port.number}')" == 80 ]]
}

t3() {
  [[ "$(jp ingress/api '{.spec.rules[*].host}')" == api.example.test ]] &&
  [[ "$(jp ingress/api '{.spec.rules[0].http.paths[0].path}')" == /v1 ]] &&
  [[ "$(jp ingress/api '{.spec.rules[0].http.paths[0].pathType}')" == Prefix ]] &&
  [[ "$(jp ingress/api '{.spec.rules[0].http.paths[0].backend.service.name}')" == api ]] &&
  [[ "$(jp ingress/api '{.spec.rules[0].http.paths[0].backend.service.port.number}')" == 8080 ]]
}

t4() {
  [[ "$(jp gateway/edge '{.spec.gatewayClassName}')" == "$LAB_GATEWAYCLASS" ]] &&
  [[ "$(jp gateway/edge '{.spec.listeners[*].name}')" == http ]] &&
  [[ "$(jp gateway/edge '{.spec.listeners[0].protocol}')" == HTTP ]] &&
  [[ "$(jp gateway/edge '{.spec.listeners[0].port}')" == 80 ]] &&
  [[ "$(jp gateway/edge '{.spec.listeners[0].hostname}')" == "*.example.test" ]]
}

t5() {
  [[ "$(jp httproute/shop-route '{.spec.parentRefs[0].name}')" == edge ]] &&
  [[ "$(jp httproute/shop-route '{.spec.hostnames[*]}')" == shop.example.test ]] &&
  [[ "$(jp httproute/shop-route '{.spec.rules[0].matches[0].path.type}')" == PathPrefix ]] &&
  [[ "$(jp httproute/shop-route '{.spec.rules[0].matches[0].path.value}')" == / ]] &&
  [[ "$(jp httproute/shop-route '{.spec.rules[0].backendRefs[0].name}')" == shop ]] &&
  [[ "$(jp httproute/shop-route '{.spec.rules[0].backendRefs[0].port}')" == 80 ]]
}

check 1 "Ingress shop: class nginx, host shop.example.test, path / (Prefix) to Service shop port 80" \
  "the path is / with pathType Prefix; 'kubectl create ingress' gives Exact unless the path ends in *" t1
check 2 "Secret docs-tls is kubernetes.io/tls; Ingress docs serves docs.example.test/docs over it" \
  "tls.hosts and tls.secretName belong in spec.tls; the secret must have tls.crt and tls.key" t2
check 3 "Ingress api: host api.example.test, path /v1 (Prefix) to Service api port 8080" \
  "the backend port is the Service port, 8080 here" t3
check 4 "Gateway edge: class $LAB_GATEWAYCLASS, one HTTP listener on port 80 for *.example.test" \
  "listeners are a list; the hostname goes on the listener" t4
check 5 "HTTPRoute shop-route attached to Gateway edge: shop.example.test, PathPrefix / to shop port 80" \
  "parentRefs names the Gateway; backendRefs names the Service" t5

finish_checks
