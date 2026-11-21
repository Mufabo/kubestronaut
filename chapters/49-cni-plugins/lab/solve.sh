#!/usr/bin/env bash
# Reference solution for the Chapter 49 lab.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster
require_cmd helm

# Tasks 1, 3, and 4 in one install (upgrade --install also works if Cilium is
# there already). --reset-values: start from the chart's defaults plus these.
helm upgrade --install cilium cilium --repo https://helm.cilium.io --version "$CILIUM_VERSION" \
  --namespace kube-system --reset-values \
  --set ipam.mode=kubernetes \
  --set routingMode=native --set autoDirectNodeRoutes=true --set ipv4NativeRoutingCIDR=10.244.0.0/16 \
  --set MTU=1400 >/dev/null
# The agents read cilium-config only when they start.
kubectl -n kube-system rollout restart daemonset/cilium >/dev/null
kubectl -n kube-system rollout status daemonset/cilium --timeout=600s >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=300s >/dev/null
kubectl -n "$LAB_NS" wait --for=condition=Ready pod/client pod/web --timeout=300s >/dev/null

# Task 2: the runtime uses the first configuration file in name order.
conf="$(docker exec kbook-worker2 sh -c 'ls -1 /etc/cni/net.d | grep -E "\.(conf|conflist|json)$" | sort | head -n1')"
echo "/etc/cni/net.d/${conf}" > "${LAB_ANSWERS}/cni-conf"
docker exec kbook-worker2 cat "/etc/cni/net.d/${conf}" |
  python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("plugins") or [d])[0]["type"])' > "${LAB_ANSWERS}/cni-plugin"
