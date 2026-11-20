#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

ns=$LAB_NS
svc() { kubectl -n "$ns" get service "$1" -o jsonpath="$2" 2>/dev/null; }
from_client() { kubectl -n "$ns" exec client -- curl -s --max-time 3 "$1" 2>/dev/null; }
from_outside() { docker exec ch53-outside curl -s --max-time 3 "$1" 2>/dev/null; }
in_cidr() { python3 -c 'import ipaddress,sys; sys.exit(ipaddress.ip_address(sys.argv[1]) not in ipaddress.ip_network(sys.argv[2]))' "$1" "$2" 2>/dev/null; }
shop_ips() { kubectl -n "$ns" get pods -l app=shop -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' 2>/dev/null | sort | xargs; }
# answered_by_shop <body>   the body is the name of a shop Pod
is_shop() { [[ "$1" == shop-* ]]; }

t1() {
  [[ "$(svc shop '{.spec.type} {.spec.ports[0].port}')" == "ClusterIP 80" ]] &&
    is_shop "$(from_client http://shop/hostname)" &&
    [[ "$(kubectl -n "$ns" get endpointslices -l kubernetes.io/service-name=shop -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}' 2>/dev/null | sort | xargs)" == "$(shop_ips)" ]]
}
t2() {
  [[ "$(kubectl -n "$ns" get deployment cart -o jsonpath='{.spec.replicas} {.spec.template.spec.containers[0].args}' 2>/dev/null)" == '2 ["netexec","--http-port=9090"]' ]] &&
    [[ "$(svc cart '{.spec.ports[0].port}')" == 80 && "$(from_client http://cart/hostname)" == cart-* ]]
}
t3() {
  local ip
  [[ "$(svc shop-public '{.spec.type} {.spec.ports[0].port} {.spec.ports[0].nodePort}')" == "NodePort 80 30017" ]] || return 1
  for ip in $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'); do
    is_shop "$(from_outside "http://${ip}:30017/hostname")" || return 1
  done
}
t4() {
  local _ names=()
  [[ "$(svc shop-sticky '{.spec.type} {.spec.ports[0].port} {.spec.sessionAffinity}')" == "ClusterIP 80 ClientIP" ]] || return 1
  for _ in 1 2 3 4 5 6 7 8; do names+=("$(from_client http://shop-sticky/hostname)"); done
  is_shop "${names[0]}" && [[ "$(printf '%s\n' "${names[@]}" | sort -u | wc -l)" == 1 ]]
}
t5() {
  local got
  [[ "$(svc shop-pods '{.spec.clusterIP}')" == None ]] || return 1
  got="$(kubectl -n "$ns" exec client -- dig +short +time=2 +tries=1 shop-pods.ch53-services.svc.cluster.local 2>/dev/null | sort | xargs)"
  [[ -n "$got" && "$got" == "$(shop_ips)" ]]
}
t6() {
  local ip
  ip="$(svc shop-lb '{.status.loadBalancer.ingress[0].ip}')"
  [[ "$(svc shop-lb '{.spec.type} {.spec.ports[0].port}')" == "LoadBalancer 80" ]] &&
    [[ "$(kubectl get ciliumloadbalancerippools.cilium.io ch53-pool -o jsonpath='{.spec.blocks[0].cidr}' 2>/dev/null)" == 172.18.17.0/29 ]] &&
    [[ -n "$ip" ]] && in_cidr "$ip" 172.18.17.0/29 &&
    answer_is "${LAB_ANSWERS}/lb-ip" "$ip" &&
    is_shop "$(from_client "http://${ip}/hostname")"
}

check 1 "Service shop (ClusterIP, port 80) sends client's requests to all three shop Pods on port 8080" \
  "kubectl expose deployment shop --port=80 --target-port=8080, or write the Service; check with kubectl get endpointslices" t1
check 2 "client gets an answer from a cart Pod at http://cart/hostname; the cart Deployment is unchanged" \
  "Compare the Service's targetPort with the port the cart containers listen on (kubectl get pod -o yaml, or kubectl describe service cart)" t2
check 3 "Service shop-public (NodePort, port 80, nodePort 30017) answers on every node's address from outside the cluster" \
  "type: NodePort with nodePort: 30017; test with docker exec ch53-outside curl http://<node-ip>:30017/hostname" t3
check 4 "Service shop-sticky (ClusterIP, port 80, sessionAffinity ClientIP) sends all of client's requests to one shop Pod" \
  "spec.sessionAffinity: ClientIP" t4
check 5 "headless Service shop-pods: shop-pods.ch53-services.svc.cluster.local resolves to the three shop Pod IPs" \
  "clusterIP: None (set it when you create the Service; it cannot be changed later)" t5
check 6 "pool ch53-pool (172.18.17.0/29) gives Service shop-lb (LoadBalancer, port 80) an IP; it is in ${LAB_ANSWERS}/lb-ip and client reaches shop through it" \
  "A CiliumLoadBalancerIPPool (apiVersion cilium.io/v2) with spec.blocks: [{cidr: 172.18.17.0/29}]; then kubectl get service shop-lb shows EXTERNAL-IP" t6
finish_checks
