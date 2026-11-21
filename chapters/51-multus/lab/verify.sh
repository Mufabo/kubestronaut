#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_lab_cluster

ns=$LAB_NS
# if_addr <pod> <interface>   the IPv4 address (with prefix) on that interface
if_addr() {
  kubectl -n "$ns" exec "$1" -- ip -4 -o addr show dev "$2" 2>/dev/null | awk '{print $4}' | head -n1
}
cilium_addr_ok() { # the Pod's primary address still comes from Cilium (10.244.0.0/16)
  local ip; ip="$(pod_ip "$ns" "$1")"
  [[ "$ip" == 10.244.* && "$(if_addr "$1" eth0)" == "${ip}/"* ]]
}
pings() { kubectl -n "$ns" exec "$1" -- ping -c1 -W2 "$2" >/dev/null 2>&1; }
on_storage() { # on_storage <pod> <interface>: the network-status lists storage on that interface
  local st
  st="$(kubectl -n "$ns" get pod "$1" -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' 2>/dev/null)"
  python3 -c 'import json,sys; s=json.loads(sys.argv[1]); sys.exit(not any(e.get("name")==sys.argv[2] and e.get("interface")==sys.argv[3] for e in s))' \
    "$st" "${ns}/storage" "$2" 2>/dev/null
}

t1() {
  local n
  [[ "$(kubectl -n kube-system get configmap cilium-config -o jsonpath='{.data.cni-exclusive}' 2>/dev/null)" == false ]] || return 1
  for n in $(kind_nodes); do
    [[ "$(first_cni_conf "$n")" == 00-multus.conf ]] || return 1
    [[ "$(docker exec "$n" cat /etc/cni/net.d/00-multus.conf 2>/dev/null)" == *'"multus-shim"'* ]] || return 1
  done
}
t2() {
  local cfg
  cfg="$(kubectl -n "$ns" get network-attachment-definition storage -o jsonpath='{.spec.config}' 2>/dev/null)"
  [[ -n "$cfg" ]] && python3 -c '
import json, sys
c = json.loads(sys.argv[1])
ok = (c.get("type") == "macvlan" and c.get("master") == "eth0" and c.get("mode") == "bridge"
      and c.get("ipam", {}).get("type") == "static" and c.get("capabilities", {}).get("ips") is True)
sys.exit(not ok)' "$cfg" 2>/dev/null
}
t3() {
  pod_phase_is "$ns" db Running && pod_phase_is "$ns" app Running &&
    [[ "$(kubectl -n "$ns" get pod db -o jsonpath='{.spec.nodeName}' 2>/dev/null)" == kbook-worker &&
       "$(kubectl -n "$ns" get pod app -o jsonpath='{.spec.nodeName}' 2>/dev/null)" == kbook-worker2 ]] &&
    [[ "$(if_addr db net1)" == 172.18.100.21/24 && "$(if_addr app net1)" == 172.18.100.22/24 ]] &&
    on_storage db net1 && on_storage app net1 &&
    cilium_addr_ok db && cilium_addr_ok app && pings app 172.18.100.21
}
t4() {
  pod_phase_is "$ns" backup Running &&
    [[ "$(if_addr backup stor0)" == 172.18.100.23/24 ]] && on_storage backup stor0 &&
    cilium_addr_ok backup && pings backup 172.18.100.21
}

check 1 "Multus is in charge on every node: Cilium's cni-exclusive is false, and each node's first CNI configuration is Multus's 00-multus.conf" \
  "Look at /etc/cni/net.d on a node: docker exec kbook-worker ls /etc/cni/net.d. Turn off cni.exclusive in Cilium (Helm), restart Cilium, then restart Multus so it writes its file again" t1
check 2 "NetworkAttachmentDefinition storage in ${ns}: macvlan on eth0 in bridge mode, static IPAM with the ips capability" \
  "Its spec.config is a CNI configuration: {\"cniVersion\":\"1.0.0\",\"type\":\"macvlan\",\"master\":\"eth0\",\"mode\":\"bridge\",\"capabilities\":{\"ips\":true},\"ipam\":{\"type\":\"static\"}}" t2
check 3 "db (kbook-worker, 172.18.100.21/24) and app (kbook-worker2, 172.18.100.22/24) run with net1 on storage, keep their Cilium addresses, and app pings db's storage address" \
  "Annotate the Pods with k8s.v1.cni.cncf.io/networks: '[{\"name\": \"storage\", \"ips\": [\"172.18.100.21/24\"]}]'; networks are attached only when a Pod starts, so recreate it" t3
check 4 "backup runs with its storage interface named stor0 (172.18.100.23/24), keeps its Cilium address, and pings db's storage address" \
  "The network selection JSON takes an \"interface\" field next to \"name\" and \"ips\"" t4
finish_checks
