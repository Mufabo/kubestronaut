#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

ns=$LAB_NS
nodes=(kbook-control-plane kbook-worker kbook-worker2)
podcidr() { kubectl get node "$1" -o jsonpath='{.spec.podCIDR}' 2>/dev/null; }
node_ip() { kubectl get node "$1" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null; }
in_cidr() { python3 -c 'import ipaddress,sys; sys.exit(ipaddress.ip_address(sys.argv[1]) not in ipaddress.ip_network(sys.argv[2]))' "$1" "$2" 2>/dev/null; }
# cfg <key>   a value from Cilium's ConfigMap (what the agents are told)
cfg() { kubectl -n kube-system get configmap cilium-config -o jsonpath="{.data.$1}" 2>/dev/null; }

all_ready() {
  local n st
  for n in "${nodes[@]}"; do
    st="$(kubectl get node "$n" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)"
    [[ "$st" == True ]] || return 1
  done
}
cilium_running() {
  local out
  out="$(kubectl -n kube-system get daemonset cilium \
    -o jsonpath='{.status.numberReady} {.spec.template.spec.containers[0].image}' 2>/dev/null)"
  [[ "${out%% *}" == 3 && "${out#* }" == *":v${CILIUM_VERSION}"* ]]
}
pod_in_node_cidr() {
  local ip; ip="$(pod_ip "$ns" "$1")"
  pod_phase_is "$ns" "$1" Running && [[ -n "$ip" ]] && in_cidr "$ip" "$(podcidr "$2")"
}
no_nat_between_pods() {
  local cip wip body
  cip="$(pod_ip "$ns" client)" wip="$(pod_ip "$ns" web)"
  [[ -n "$cip" && -n "$wip" ]] || return 1
  body="$(kubectl -n "$ns" exec client -- curl -s --max-time 3 "http://${wip}:8080/clientip" 2>/dev/null)"
  [[ "${body%:*}" == "$cip" ]]
}
# routed_direct <from> <to>   <from> sends <to>'s Pod CIDR straight to <to>'s address
routed_direct() {
  local r; r="$(docker exec "$1" ip route show "$(podcidr "$2")" 2>/dev/null)"
  [[ -n "$r" && "$r" == *"via $(node_ip "$2") dev eth0"* ]]
}
# cni_conf_path   the configuration file the runtime on kbook-worker2 uses: the
# first .conf/.conflist/.json file in /etc/cni/net.d, in name order
cni_conf_path() {
  local f
  f="$(docker exec kbook-worker2 sh -c 'cd /etc/cni/net.d 2>/dev/null && ls -1 | grep -E "\.(conf|conflist|json)$" | sort | head -n1' 2>/dev/null)"
  [[ -n "$f" ]] && printf '/etc/cni/net.d/%s' "$f"
}
cni_plugin_type() {
  local p; p="$(cni_conf_path)" || return 1
  docker exec kbook-worker2 cat "$p" 2>/dev/null |
    python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("plugins") or [d])[0]["type"])' 2>/dev/null
}
pod_mtu() { kubectl -n "$ns" exec "$1" -- cat /sys/class/net/eth0/mtu 2>/dev/null; }

t1() {
  cilium_running && [[ "$(cfg ipam)" == kubernetes ]] && all_ready &&
    pod_in_node_cidr client kbook-worker && pod_in_node_cidr web kbook-worker2
}
t2() {
  local want_path want_type
  want_path="$(cni_conf_path)" && want_type="$(cni_plugin_type)" &&
    answer_is "${LAB_ANSWERS}/cni-conf" "$want_path" && answer_is "${LAB_ANSWERS}/cni-plugin" "$want_type"
}
t3() {
  [[ "$(cfg routing-mode)" == native && "$(cfg auto-direct-node-routes)" == true &&
     "$(cfg ipv4-native-routing-cidr)" == 10.244.0.0/16 ]] &&
    routed_direct kbook-worker kbook-worker2 && routed_direct kbook-worker2 kbook-worker &&
    no_nat_between_pods
}
t4() {
  [[ "$(cfg mtu)" == 1400 && "$(pod_mtu client)" == 1400 && "$(pod_mtu web)" == 1400 ]] && no_nat_between_pods
}

check 1 "Cilium ${CILIUM_VERSION} runs on all three nodes with Kubernetes host-scope IPAM; the nodes are Ready, and client and web run with addresses from their own node's Pod CIDR" \
  "helm install cilium cilium --repo https://helm.cilium.io --version ${CILIUM_VERSION} -n kube-system --set ipam.mode=kubernetes (the chart's default IPAM ignores the nodes' podCIDR)" t1
check 2 "${LAB_ANSWERS}/cni-conf holds the path of the CNI configuration kbook-worker2 uses, and ${LAB_ANSWERS}/cni-plugin its plugin type" \
  "Look on the node: docker exec kbook-worker2 ls /etc/cni/net.d, then read the file's \"type\"" t2
check 3 "Cilium routes natively (routing-mode native, auto-direct-node-routes, native routing CIDR 10.244.0.0/16): each worker sends the other's Pod CIDR to its node address on eth0, and client still reaches web without NAT" \
  "helm upgrade ... --reuse-values --set routingMode=native --set autoDirectNodeRoutes=true --set ipv4NativeRoutingCIDR=10.244.0.0/16; the agents read their config only when they start" t3
check 4 "Cilium's MTU is 1400, and eth0 in client and in web has MTU 1400; client still reaches web" \
  "helm upgrade ... --reuse-values --set MTU=1400, then restart the cilium DaemonSet; check with kubectl exec client -- cat /sys/class/net/eth0/mtu" t4
finish_checks
