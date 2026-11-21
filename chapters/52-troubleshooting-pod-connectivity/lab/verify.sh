#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

ns=$LAB_NS
node_of() { kubectl -n "$ns" get pod "$1" -o jsonpath='{.spec.nodeName}' 2>/dev/null; }
# host_veth   the node-side interface of web's eth0 on its node: the interface
# whose index is web's eth0 "iflink"
host_veth() {
  local idx node
  idx="$(kubectl -n "$ns" exec web -- cat /sys/class/net/eth0/iflink 2>/dev/null | tr -d '[:space:]')"
  node="$(node_of web)"
  [[ -n "$idx" && -n "$node" ]] || return 1
  docker exec "$node" ip -o link 2>/dev/null | awk -F': ' -v n="$idx" '$1 == n {sub(/@.*/, "", $2); print $2}'
}
api_ip() {
  kubectl -n "$ns" get pods -l app=api --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].status.podIP}' 2>/dev/null
}

t1() {
  local v; v="$(host_veth)"
  [[ -n "$v" ]] && answer_is "${LAB_ANSWERS}/web-veth" "$v"
}
t2() {
  local ip out
  ip="$(api_ip)"; [[ -n "$ip" ]] || return 1
  out="$(kubectl -n "$ns" exec client -- nc -w 2 "$ip" 8080 </dev/null 2>/dev/null)"
  [[ "$out" == *api-ok* ]]
}
t3() {
  local wip
  wip="$(pod_ip "$ns" web)"
  [[ "$(node_of web)" == kbook-worker2 && "$(node_of client)" == kbook-worker && -n "$wip" ]] &&
    [[ "$(kubectl -n kube-system get configmap cilium-config -o jsonpath='{.data.routing-mode}' 2>/dev/null)" == tunnel ]] &&
    [[ "$(kubectl -n "$ns" exec client -- curl -s --max-time 3 "http://${wip}:8080/hostname" 2>/dev/null)" == web ]]
}
t4() {
  local svc got
  svc="$(kubectl -n "$ns" get service web -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"
  got="$(kubectl -n "$ns" exec client -- dig +short +time=2 +tries=1 web.ch52-debug.svc.cluster.local 2>/dev/null | head -n1)"
  [[ -n "$svc" && "$got" == "$svc" && "$(node_of client)" == kbook-worker &&
     "$(kubectl -n "$ns" get pod client -o jsonpath='{.spec.dnsPolicy}' 2>/dev/null)" == ClusterFirst ]]
}

check 1 "${LAB_ANSWERS}/web-veth holds the name of web's host-side interface on its node (without the @ part)" \
  "Inside web: cat /sys/class/net/eth0/iflink gives an interface index; on the node, ip -o link shows which interface has it" t1
check 2 "client gets 'api-ok' from the api Pod's address on port 8080" \
  "Look at what api listens on: kubectl debug -it <api-pod> --image=nicolaka/netshoot:v0.14 --target=api -- ss -lnt" t2
check 3 "client (kbook-worker) reaches web (kbook-worker2) at its Pod IP on port 8080, with Cilium still in tunnel mode" \
  "Capture on both nodes (kubectl debug node/... -- tcpdump -n -i eth0 udp port 8472): where do the packets stop? Then look at that node's firewall" t3
check 4 "client, still on kbook-worker, resolves web.ch52-debug.svc.cluster.local to the Service's ClusterIP through cluster DNS (dnsPolicy ClusterFirst)" \
  "Compare client's /etc/resolv.conf with another Pod's; the DNS policy is part of the Pod spec, so recreate the Pod" t4
finish_checks
