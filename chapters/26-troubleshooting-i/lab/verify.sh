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
# ready_ips <service>: the sorted IPs of the Service's ready endpoints
ready_ips() {
  k get endpointslices -l "kubernetes.io/service-name=$1" \
    -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{"\n"}{end}' 2>/dev/null | sort
}
# pod_ips <label-selector>: the sorted IPs of the matching Pods
pod_ips() { k get pods -l "$1" -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' 2>/dev/null | sort; }

t1() {
  [[ "$(jp deployment/api '{.spec.template.spec.containers[0].image}')" == nginx:1.27 ]] &&
  [[ "$(jp deployment/api '{.status.readyReplicas}')" == 1 ]]
}

t2() {
  local got want
  got="$(ready_ips web)"
  want="$(pod_ips app=web)"
  [[ -n "$want" && "$got" == "$want" ]]
}

t3() {
  local got want
  [[ "$(jp service/app '{.spec.ports[0].targetPort}')" == 8080 ]] || return 1
  got="$(ready_ips app)"
  want="$(pod_ips app=app)"
  [[ -n "$want" && "$got" == "$want" ]]
}

t4() {
  # the policy admits the client's role on port 8080, and the client reaches the app Pod
  [[ "$(jp networkpolicy/lock '{.spec.ingress[0].from[0].podSelector.matchLabels.role}')" == client ]] || return 1
  local ip
  ip="$(pod_ips app=app | head -1)"
  [[ -n "$ip" ]] && k exec client -- sh -c "curl -s -m 5 http://${ip}:8080/" 2>/dev/null | grep -q app-ok
}

t5() {
  local out
  out="$(k exec resolver -- nslookup kubernetes.default.svc.cluster.local 2>/dev/null || true)"
  grep -Fq "Name:" <<<"$out" && grep -Fq "kubernetes.default.svc.cluster.local" <<<"$out" &&
  grep -Fq "Address" <<<"$out" && [[ "$(jp pod/resolver '{.status.phase}')" == Running ]]
}

check 1 "Deployment api runs image nginx:1.27 and is ready (Fault: a typo in the image tag)" \
  "kubectl -n ${LAB_NS} describe pod: the events name the image that cannot be pulled" t1
check 2 "Service web has the ready endpoints of the web Pods (Fault: a typo in the selector)" \
  "kubectl -n ${LAB_NS} get endpointslices -l kubernetes.io/service-name=web: an empty list means no Pod matches" t2
check 3 "Service app sends traffic to targetPort 8080, and has the app Pod as an endpoint" \
  "compare the Service's ports with the containerPort the app listens on" t3
check 4 "NetworkPolicy lock admits role=client on port 8080, and the client reaches the app Pod" \
  "kubectl describe networkpolicy lock shows which Pods it selects and what it admits" t4
check 5 "Pod resolver resolves kubernetes.default.svc.cluster.local with a nameserver that answers" \
  "the Pod's dnsConfig sets its nameservers; kube-dns runs in kube-system" t5

finish_checks
