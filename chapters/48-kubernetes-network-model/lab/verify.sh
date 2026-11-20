#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

ns=$LAB_NS
podcidr() { kubectl get node "$1" -o jsonpath='{.spec.podCIDR}' 2>/dev/null; }
node_ip() { kubectl get node "$1" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null; }
in_cidr() { python3 -c 'import ipaddress,sys; sys.exit(ipaddress.ip_address(sys.argv[1]) not in ipaddress.ip_network(sys.argv[2]))' "$1" "$2" 2>/dev/null; }
# from_client <url>   the body client gets back (3 s timeout)
from_client() { kubectl -n "$ns" exec client -- curl -s --max-time 3 "$1" 2>/dev/null; }
# seen_as <url>   the source address the server saw (agnhost /clientip prints ip:port)
seen_as() { local b; b="$(from_client "$1")"; printf '%s' "${b%:*}"; }

all_ready() {
  local n st
  for n in kbook-control-plane kbook-worker kbook-worker2; do
    st="$(kubectl get node "$n" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)"
    [[ "$st" == True ]] || return 1
  done
}
pod_in_node_cidr() {
  local ip; ip="$(pod_ip "$ns" "$1")"
  pod_phase_is "$ns" "$1" Running && [[ -n "$ip" ]] && in_cidr "$ip" "$(podcidr "$2")"
}
no_nat_between_pods() {
  local cip wip
  cip="$(pod_ip "$ns" client)" wip="$(pod_ip "$ns" web)"
  [[ -n "$cip" && -n "$wip" && "$(seen_as "http://${wip}:8080/clientip")" == "$cip" ]]
}

t1() { answer_is "${LAB_ANSWERS}/podcidr" "$(podcidr kbook-worker2)"; }
t2() { all_ready && pod_in_node_cidr client kbook-worker && pod_in_node_cidr web kbook-worker2; }
t3() { no_nat_between_pods; }
t4() { pod_resolves "$ns" client web.ch48-cni.svc.cluster.local && [[ "$(from_client http://web:8080/hostname)" == web ]]; }
t5() {
  local out; out="$(cat "${here}/.state/outside-ip" 2>/dev/null)"
  [[ -n "$out" && "$(seen_as "http://${out}:8080/clientip")" == "$(node_ip kbook-worker)" ]] && no_nat_between_pods
}

check 1 "${LAB_ANSWERS}/podcidr holds the Pod CIDR of node kbook-worker2" \
  "Each node's range is in its spec: kubectl get node kbook-worker2 -o jsonpath='{.spec.podCIDR}'" t1
check 2 "all three nodes are Ready, and client and web run with addresses from their own node's Pod CIDR" \
  "Write a CNI configuration (ptp plugin, host-local IPAM with the node's podCIDR) to /etc/cni/net.d/ on every node: docker exec -it kbook-worker bash" t2
check 3 "client reaches web's Pod IP on port 8080, and web sees client's real Pod IP (no NAT)" \
  "Each node needs a route to every other node's Pod CIDR via that node's address; keep ipMasq off in the CNI config" t3
check 4 "client resolves web.ch48-cni.svc.cluster.local and gets 'web' from http://web:8080/hostname" \
  "CoreDNS runs as Pods too: every node, the control plane included, needs routes to every other node's Pod CIDR" t4
check 5 "client reaches the outside server, which sees kbook-worker's node address; Pod-to-Pod traffic is still not NATed" \
  "The outside server has no route back to 10.244.0.0/16. On every node: masquerade traffic from 10.244.0.0/16 to anything outside 10.244.0.0/16" t5
finish_checks
