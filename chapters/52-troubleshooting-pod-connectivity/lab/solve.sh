#!/usr/bin/env bash
# Reference solution for the Chapter 52 lab.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster
ns=$LAB_NS

# Task 1: web's eth0 is one end of a veth pair; iflink is the index of the other end.
idx="$(kubectl -n "$ns" exec web -- cat /sys/class/net/eth0/iflink | tr -d '[:space:]')"
node_exec kbook-worker2 ip -o link | awk -F': ' -v n="$idx" '$1 == n {sub(/@.*/, "", $2); print $2}' > "${LAB_ANSWERS}/web-veth"

# Task 2: listen on every address, not only on the loopback.
kubectl -n "$ns" patch deployment api --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/command/1","value":"TCP-LISTEN:8080,bind=0.0.0.0,fork,reuseaddr"}]' >/dev/null
kubectl -n "$ns" rollout status deployment/api --timeout=300s >/dev/null

# Task 3: the firewall rule on kbook-worker2 drops Cilium's VXLAN packets.
while node_exec kbook-worker2 iptables -C INPUT -p udp --dport 8472 -j DROP 2>/dev/null; do
  node_exec kbook-worker2 iptables -D INPUT -p udp --dport 8472 -j DROP
done

# Task 4: recreate client with the default DNS policy (ClusterFirst).
kubectl -n "$ns" get pod client -o json |
  python3 -c 'import json,sys; p=json.load(sys.stdin); p["spec"]["dnsPolicy"]="ClusterFirst"
m=p["metadata"]; p["metadata"]={"name": m["name"], "namespace": m["namespace"], "labels": m.get("labels", {})}
p.pop("status", None); print(json.dumps(p))' |
  kubectl -n "$ns" replace --force -f - >/dev/null
kubectl -n "$ns" wait --for=condition=Ready pod/client --timeout=300s >/dev/null
