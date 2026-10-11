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
# ready_ips <service>: the sorted IPs of the Service's ready endpoints (EndpointSlices)
ready_ips() {
  k get endpointslices -l "kubernetes.io/service-name=$1" \
    -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{"\n"}{end}' 2>/dev/null | sort
}
# pod_ips <label-selector>: the sorted IPs of the Pods that match it
pod_ips() {
  k get pods -l "$1" -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' 2>/dev/null | sort
}
# serves <service> <app-label>: the Service's ready endpoints are exactly the Pods with that label
serves() {
  local got want
  got="$(ready_ips "$1")"
  want="$(pod_ips "app=$2")"
  [[ -n "$want" && "$got" == "$want" ]]
}
# dns_has <name> <text>: the lab's DNS client resolves <name> and the answer contains <text>
dns_has() {
  local out
  out="$(k exec dns-client -- nslookup "$1" 2>/dev/null || true)"
  grep -Fq -- "$2" <<<"$out"
}

t1() {
  [[ "$(jp svc/web '{.spec.type}')" == ClusterIP ]] &&
  [[ "$(jp svc/web '{.spec.ports[0].port}')" == 80 ]] &&
  [[ "$(jp svc/web '{.spec.ports[0].targetPort}')" == 80 ]] &&
  [[ "$(jp svc/web '{.spec.selector.app}')" == web ]] &&
  serves web web
}

t2() {
  [[ "$(jp svc/web-np '{.spec.type}')" == NodePort ]] &&
  [[ "$(jp svc/web-np '{.spec.ports[0].nodePort}')" == 30080 ]] &&
  [[ "$(jp svc/web-np '{.spec.selector.app}')" == web ]] &&
  serves web-np web
}

t3() {
  [[ "$(jp svc/web-headless '{.spec.clusterIP}')" == None ]] &&
  [[ "$(jp svc/web-headless '{.spec.selector.app}')" == web ]] || return 1
  # DNS returns one address per ready Pod, so every Pod IP must appear in the answer
  local ip
  while IFS= read -r ip; do
    [[ -n "$ip" ]] || continue
    dns_has web-headless "$ip" || return 1
  done < <(pod_ips app=web)
  [[ -n "$(pod_ips app=web)" ]]
}

t4() {
  [[ "$(jp svc/legacy '{.spec.type}')" == ExternalName ]] &&
  [[ "$(jp svc/legacy '{.spec.externalName}')" == db.example.internal ]] &&
  dns_has legacy "canonical name = db.example.internal"
}

t5() {
  [[ "$(jp svc/api '{.spec.selector.app}')" == api ]] &&
  serves api api
}

check 1 "Service web (ClusterIP, port 80 to 80, selector app=web) routes to every ready web Pod" \
  "kubectl -n ${LAB_NS} get endpointslices -l kubernetes.io/service-name=web shows the Pod IPs" t1
check 2 "Service web-np is a NodePort on 30080 that routes to the web Pods" \
  "the nodePort field is under .spec.ports[0]" t2
check 3 "Service web-headless has no cluster IP, and DNS returns the IP of every web Pod" \
  "a headless Service is created with --cluster-ip=None; check with nslookup from dns-client" t3
check 4 "Service legacy is an ExternalName Service for db.example.internal, and DNS returns that name" \
  "use the ExternalName type with --external-name; a lookup gives a canonical name" t4
check 5 "Service api selects the api Pods again, and routes to every ready one" \
  "the selector must match the labels on the Pods exactly" t5

finish_checks
