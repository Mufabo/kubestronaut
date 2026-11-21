#!/usr/bin/env bash
# Reference solution for the Part VI simulator.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_lab_cluster
C=$COURSE
k() { kubectl --context "kind-${CLUSTER_NAME}" "$@"; }

# 1: Multus's file comes first; its clusterNetwork is Cilium's file.
conf="$(first_cni_conf kbook-worker2)"
echo "/etc/cni/net.d/${conf}" > "${C}/1/conf"
cn="$(docker exec kbook-worker2 cat "/etc/cni/net.d/${conf}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["clusterNetwork"])')"
docker exec kbook-worker2 cat "${cn#/host}" |
  python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("plugins") or [d])[0]["type"])' > "${C}/1/cluster-network"

# 2
docker exec kbook-control-plane cat /etc/kubernetes/manifests/kube-controller-manager.yaml |
  sed -n 's/.*--cluster-cidr=\([^ ]*\).*/\1/p' | head -n1 > "${C}/2/cluster-cidr"
k -n kube-system get configmap cilium-config -o jsonpath='{.data.ipam}' > "${C}/2/ipam"
echo default > "${C}/2/probe-pool"

# 3 and 4
k apply -f - >/dev/null <<'YAML'
apiVersion: cilium.io/v2alpha1
kind: CiliumPodIPPool
metadata:
  name: red
spec:
  ipv4:
    cidrs: ["10.21.0.0/16"]
    maskSize: 27
---
apiVersion: cilium.io/v2alpha1
kind: CiliumPodIPPool
metadata:
  name: small
spec:
  ipv4:
    cidrs: ["10.31.0.0/27", "10.31.1.0/26"]
    maskSize: 28
YAML

# 5
k -n p6-fabric delete pod sensor --ignore-not-found --wait=true >/dev/null
k -n p6-fabric apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: sensor
  annotations:
    k8s.v1.cni.cncf.io/networks: '[{"name": "fabric", "ips": ["172.18.110.5/24"], "interface": "fab0"}]'
spec:
  nodeSelector: {kubernetes.io/hostname: kbook-worker2}
  terminationGracePeriodSeconds: 0
  containers:
    - name: sensor
      image: nicolaka/netshoot:v0.14
      command: ["sleep", "infinity"]
YAML

# 6
k -n p6-shop patch deployment cart --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/command/1","value":"TCP-LISTEN:9000,bind=0.0.0.0,fork,reuseaddr"}]' >/dev/null

# 7: the FORWARD rule on kbook-worker2 drops Pod traffic arriving from other nodes.
while node_exec kbook-worker2 iptables -C FORWARD -s 10.0.0.0/8 -d 10.0.0.0/8 -i eth0 -j DROP 2>/dev/null; do
  node_exec kbook-worker2 iptables -D FORWARD -s 10.0.0.0/8 -d 10.0.0.0/8 -i eth0 -j DROP
done

# 8: recreate lookup with the default DNS policy.
k -n p6-core get pod lookup -o json |
  python3 -c 'import json,sys; p=json.load(sys.stdin); s=p["spec"]; s["dnsPolicy"]="ClusterFirst"; s.pop("dnsConfig", None)
m=p["metadata"]; p["metadata"]={"name": m["name"], "namespace": m["namespace"], "labels": m.get("labels", {})}
p.pop("status", None); print(json.dumps(p))' |
  k -n p6-core replace --force -f - >/dev/null

k -n p6-red rollout status deployment/web --timeout=600s >/dev/null
k -n p6-batch rollout status deployment/worker --timeout=600s >/dev/null
k -n p6-shop rollout status deployment/cart --timeout=300s >/dev/null
k -n p6-fabric wait --for=condition=Ready pod/sensor --timeout=300s >/dev/null
k -n p6-core wait --for=condition=Ready pod/lookup --timeout=300s >/dev/null
