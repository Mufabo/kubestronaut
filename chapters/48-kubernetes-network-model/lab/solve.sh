#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

nodes=(kbook-control-plane kbook-worker kbook-worker2)
declare -A cidr ip
for n in "${nodes[@]}"; do
  cidr[$n]="$(kubectl get node "$n" -o jsonpath='{.spec.podCIDR}')"
  ip[$n]="$(kubectl get node "$n" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')"
done

# Task 1: the answer file
echo "${cidr[kbook-worker2]}" > "${LAB_ANSWERS}/podcidr"

for n in "${nodes[@]}"; do
  # Task 2: a CNI configuration: ptp wires each Pod, host-local hands out
  # addresses from this node's Pod CIDR.
  node_exec "$n" tee /etc/cni/net.d/10-kbook.conflist >/dev/null <<JSON
{
  "cniVersion": "1.0.0",
  "name": "kbook",
  "plugins": [
    {
      "type": "ptp",
      "ipMasq": false,
      "ipam": {
        "type": "host-local",
        "ranges": [[{"subnet": "${cidr[$n]}"}]],
        "routes": [{"dst": "0.0.0.0/0"}]
      }
    },
    {"type": "portmap", "capabilities": {"portMappings": true}}
  ]
}
JSON
  # Tasks 3 and 4: a route to every other node's Pod CIDR
  for m in "${nodes[@]}"; do
    [[ "$m" == "$n" ]] && continue
    node_exec "$n" ip route replace "${cidr[$m]}" via "${ip[$m]}"
  done
  # Task 5: masquerade traffic that leaves the Pod network
  node_exec "$n" sh -c 'iptables -t nat -C POSTROUTING -s 10.244.0.0/16 ! -d 10.244.0.0/16 -j MASQUERADE 2>/dev/null ||
    iptables -t nat -A POSTROUTING -s 10.244.0.0/16 ! -d 10.244.0.0/16 -j MASQUERADE'
done

wait_for "all nodes Ready" 180 kubectl wait --for=condition=Ready nodes --all --timeout=5s
wait_for "client and web running" 240 kubectl -n "$LAB_NS" wait --for=condition=Ready pod/client pod/web --timeout=5s
wait_for "CoreDNS running" 180 kubectl -n kube-system rollout status deployment/coredns --timeout=5s
