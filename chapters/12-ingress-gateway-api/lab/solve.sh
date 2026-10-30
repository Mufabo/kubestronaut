#!/usr/bin/env bash
# Automated reference solution (used by CI). Human-readable version: solutions.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

k() { kubectl -n "$LAB_NS" "$@"; }

# Task 1
k create ingress shop --class=nginx --rule='shop.example.test/*=shop:80' >/dev/null

# Task 2
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=docs.example.test" \
  -keyout "${tmp}/tls.key" -out "${tmp}/tls.crt" >/dev/null 2>&1
k create secret tls docs-tls --cert="${tmp}/tls.crt" --key="${tmp}/tls.key" >/dev/null
k apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: docs
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - docs.example.test
      secretName: docs-tls
  rules:
    - host: docs.example.test
      http:
        paths:
          - path: /docs
            pathType: Prefix
            backend:
              service:
                name: docs
                port:
                  number: 80
YAML

# Task 3
k apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api
spec:
  ingressClassName: nginx
  rules:
    - host: api.example.test
      http:
        paths:
          - path: /v1
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 8080
YAML

# Task 4
k apply -f - >/dev/null <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: edge
spec:
  gatewayClassName: ${LAB_GATEWAYCLASS}
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "*.example.test"
YAML

# Task 5
k apply -f - >/dev/null <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: shop-route
spec:
  parentRefs:
    - name: edge
  hostnames:
    - shop.example.test
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: shop
          port: 80
YAML

# Task 6: the controller, then the Ingress, then wait for real traffic
helm repo add traefik https://traefik.github.io/charts --force-update >/dev/null
helm install "$CONTROLLER_RELEASE" traefik/traefik --version "$TRAEFIK_CHART_VERSION" \
  --namespace "$CONTROLLER_NS" --create-namespace \
  --set service.spec.type=ClusterIP --set ingressClass.isDefaultClass=false --wait --timeout 5m >/dev/null
k create ingress web --class=traefik --rule="web.example.test/*=web:80" >/dev/null
routes() {
  [[ "$(k exec client -- wget -q -T 5 -O - --header "Host: web.example.test" "http://traefik.${CONTROLLER_NS}.svc.cluster.local" 2>/dev/null)" == "hello from web" ]]
}
wait_for "web.example.test answered through Traefik" 180 routes
