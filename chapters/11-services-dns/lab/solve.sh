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
k expose deployment web --name=web --port=80 --target-port=80 >/dev/null

# Task 2
k expose deployment web --name=web-np --type=NodePort --port=80 --target-port=80 >/dev/null
k patch svc web-np -p '{"spec":{"ports":[{"port":80,"targetPort":80,"nodePort":30080}]}}' >/dev/null

# Task 3
k expose deployment web --name=web-headless --cluster-ip=None --port=80 --target-port=80 >/dev/null

# Task 4
k create service externalname legacy --external-name=db.example.internal >/dev/null

# Task 5
k patch svc api -p '{"spec":{"selector":{"app":"api"}}}' >/dev/null

# Task 6
k expose deployment web --name=web-lb --type=LoadBalancer --port=8080 --target-port=80 >/dev/null

# Let the EndpointSlices catch up before the checks run
for d in web api; do
  wait_for "Service ${d} endpoints" 120 bash -c \
    "[[ \$(kubectl -n ${LAB_NS} get endpointslices -l kubernetes.io/service-name=${d} -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{\"\\n\"}{end}' | wc -l) -eq 2 ]]"
done
lb_answers() {
  local ip out
  ip="$(k get svc web-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)"
  [[ -n "$ip" ]] || return 1
  out="$(docker exec "$LAB_OUTSIDE" curl -s --max-time 3 "http://${ip}:8080/" 2>/dev/null)"
  grep -q "Welcome to nginx" <<<"$out"
}
wait_for "web-lb answers from outside the cluster" 120 lb_answers
