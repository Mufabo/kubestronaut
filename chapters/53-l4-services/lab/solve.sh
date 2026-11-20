#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster
ns=$LAB_NS

# Task 1: a ClusterIP Service in front of shop
kubectl -n "$ns" expose deployment shop --port=80 --target-port=8080 >/dev/null
# Task 2: cart listens on 9090 (its port is named "api")
kubectl -n "$ns" patch service cart --type=json \
  -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":"api"}]' >/dev/null

kubectl -n "$ns" apply -f - >/dev/null <<'YAML'
# Task 3: a fixed NodePort
apiVersion: v1
kind: Service
metadata:
  name: shop-public
spec:
  type: NodePort
  selector: {app: shop}
  ports:
    - port: 80
      targetPort: http
      nodePort: 30017
---
# Task 4: session affinity
apiVersion: v1
kind: Service
metadata:
  name: shop-sticky
spec:
  selector: {app: shop}
  sessionAffinity: ClientIP
  ports:
    - port: 80
      targetPort: 8080
---
# Task 5: headless
apiVersion: v1
kind: Service
metadata:
  name: shop-pods
spec:
  clusterIP: None
  selector: {app: shop}
  ports:
    - port: 8080
---
# Task 6: a LoadBalancer Service
apiVersion: v1
kind: Service
metadata:
  name: shop-lb
spec:
  type: LoadBalancer
  selector: {app: shop}
  ports:
    - port: 80
      targetPort: 8080
YAML
# Task 6: the address pool Cilium's LB-IPAM hands out from
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: ch53-pool
spec:
  blocks:
    - cidr: 172.18.17.0/29
YAML
lb_ip() { kubectl -n "$ns" get service shop-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}'; }
has_lb_ip() { [[ -n "$(lb_ip)" ]]; }
wait_for "an external IP for shop-lb" 60 has_lb_ip
lb_ip > "${LAB_ANSWERS}/lb-ip"
