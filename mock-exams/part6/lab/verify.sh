#!/usr/bin/env bash
# Score the Part VI simulator. Read-only. One check per question (all or
# nothing), then the weighted score against the pass mark.
set -uo pipefail
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
in_cidrs() {
  python3 -c 'import ipaddress,sys; ip=ipaddress.ip_address(sys.argv[1]); sys.exit(not any(ip in ipaddress.ip_network(c) for c in sys.argv[2:]))' "$@" 2>/dev/null
}
pool_cidrs() { k get ciliumpodippool "$1" -o jsonpath='{.spec.ipv4.cidrs[*]}' 2>/dev/null; }
pool_mask() { k get ciliumpodippool "$1" -o jsonpath='{.spec.ipv4.maskSize}' 2>/dev/null; }
running_ips() { # running_ips <namespace> <app>
  k -n "$1" get pods -l "app=$2" --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' 2>/dev/null
}
all_in() { # all_in <namespace> <app> <count> <cidr>...
  local ns=$1 app=$2 want=$3 ip n=0; shift 3
  for ip in $(running_ips "$ns" "$app"); do in_cidrs "$ip" "$@" || return 1; n=$((n + 1)); done
  ((n == want))
}
ready() { k -n "$1" get deployment "$2" -o jsonpath='{.status.readyReplicas}' 2>/dev/null; }
node_of() { k -n "$1" get pod "$2" -o jsonpath='{.spec.nodeName}' 2>/dev/null; }
if_addr() { k -n "$1" exec "$2" -- ip -4 -o addr show dev "$3" 2>/dev/null | awk '{print $4}' | head -n1; }

q1() {
  local conf cn
  conf="$(first_cni_conf kbook-worker2)"; [[ -n "$conf" ]] || return 1
  cn="$(docker exec kbook-worker2 cat "/etc/cni/net.d/${conf}" 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("clusterNetwork",""))' 2>/dev/null)"
  cn="${cn#/host}"
  [[ -n "$cn" ]] || return 1
  answer_is "${C}/1/conf" "/etc/cni/net.d/${conf}" &&
    answer_is "${C}/1/cluster-network" "$(docker exec kbook-worker2 cat "$cn" 2>/dev/null |
      python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("plugins") or [d])[0]["type"])' 2>/dev/null)"
}
q2() {
  local cidr ip pool
  cidr="$(docker exec kbook-control-plane cat /etc/kubernetes/manifests/kube-controller-manager.yaml 2>/dev/null |
    sed -n 's/.*--cluster-cidr=\([^ ]*\).*/\1/p' | head -n1)"
  ip="$(k -n p6-core get pod probe -o jsonpath='{.status.podIP}' 2>/dev/null)"
  pool=""
  for p in $(k get ciliumpodippools -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    # shellcheck disable=SC2046  # the CIDR list is meant to be split
    in_cidrs "$ip" $(pool_cidrs "$p") && pool="$p"
  done
  [[ -n "$cidr" && -n "$pool" ]] &&
    answer_is "${C}/2/cluster-cidr" "$cidr" &&
    answer_is "${C}/2/ipam" "$(k -n kube-system get configmap cilium-config -o jsonpath='{.data.ipam}' 2>/dev/null)" &&
    answer_is "${C}/2/probe-pool" "$pool"
}
q3() {
  [[ "$(pool_cidrs red)" == 10.21.0.0/16 && "$(pool_mask red)" == 27 && "$(ready p6-red web)" == 2 ]] &&
    all_in p6-red web 2 10.21.0.0/16
}
# shellcheck disable=SC2086  # CIDR lists are meant to be split
q4() {
  local cidrs c
  cidrs="$(pool_cidrs small)"
  [[ " $cidrs " == *" 10.31.0.0/27 "* && "$(pool_mask small)" == 28 ]] || return 1
  for c in $cidrs; do
    python3 -c 'import ipaddress,sys; sys.exit(not ipaddress.ip_network(sys.argv[1]).subnet_of(ipaddress.ip_network("10.31.0.0/16")))' "$c" 2>/dev/null || return 1
  done
  [[ "$(k -n p6-batch get deployment worker -o jsonpath='{.spec.replicas}' 2>/dev/null)" == 36 &&
     "$(k get namespace p6-batch -o jsonpath='{.metadata.annotations.ipam\.cilium\.io/ip-pool}' 2>/dev/null)" == small &&
     "$(ready p6-batch worker)" == 36 ]] && all_in p6-batch worker 36 $cidrs
}
q5() {
  [[ "$(node_of p6-fabric sensor)" == kbook-worker2 && "$(if_addr p6-fabric sensor fab0)" == 172.18.110.5/24 ]] &&
    [[ "$(k -n p6-fabric get pod sensor -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)" == nicolaka/netshoot:v0.14 ]] &&
    k -n p6-fabric exec sensor -- ping -c1 -W2 172.18.110.4 >/dev/null 2>&1
}
q6() {
  local ip out
  ip="$(running_ips p6-shop cart | head -n1)"; [[ -n "$ip" ]] || return 1
  out="$(k -n p6-core exec probe -- nc -w 2 "$ip" 9000 </dev/null 2>/dev/null)"
  [[ "$out" == *cart-ok* ]]
}
q7() {
  local ip
  ip="$(k -n p6-core get pod echo -o jsonpath='{.status.podIP}' 2>/dev/null)"
  [[ -n "$ip" && "$(node_of p6-core echo)" == kbook-worker2 && "$(node_of p6-core probe)" == kbook-worker ]] &&
    [[ "$(k -n kube-system get configmap cilium-config -o jsonpath='{.data.routing-mode}' 2>/dev/null)" == native ]] &&
    [[ "$(k -n p6-core exec probe -- curl -s --max-time 3 "http://${ip}:8080/hostname" 2>/dev/null)" == echo ]]
}
q8() {
  local svc got
  svc="$(k -n p6-core get service echo -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"
  got="$(k -n p6-core exec lookup -- dig +short +time=2 +tries=1 echo.p6-core.svc.cluster.local 2>/dev/null | head -n1)"
  [[ -n "$svc" && "$got" == "$svc" && "$(node_of p6-core lookup)" == kbook-worker &&
     "$(k -n p6-core get pod lookup -o jsonpath='{.spec.dnsPolicy}' 2>/dev/null)" == ClusterFirst ]]
}

check_weighted 1 10 "${C}/1/conf holds the CNI configuration kbook-worker2 uses, and ${C}/1/cluster-network its cluster network's plugin type" \
  "the first file in /etc/cni/net.d is Multus's; its clusterNetwork names the file whose type you need" q1
check_weighted 2 8 "${C}/2 holds the cluster CIDR, Cilium's IPAM mode, and the pool probe's address comes from" \
  "--cluster-cidr in the controller manager's manifest; cilium config view; kubectl get ciliumpodippools" q2
check_weighted 3 12 "(p6-red) pool red (10.21.0.0/16, /27 blocks) exists, and both web Pods run with addresses from it" \
  "kubectl describe pod shows which pool the Pods wait for" q3
check_weighted 4 12 "(p6-batch) pool small still holds 10.31.0.0/27 and only ranges inside 10.31.0.0/16; worker has 36 ready replicas from it" \
  "add a range to spec.ipv4.cidrs of the pool" q4
check_weighted 5 16 "(p6-fabric) Pod sensor on kbook-worker2 has fab0 = 172.18.110.5/24 on fabric and pings 172.18.110.4" \
  "the network selection annotation takes name, ips, and interface" q5
check_weighted 6 10 "(p6-shop) probe gets cart-ok from the cart Pod on port 9000" \
  "check what cart listens on with an ephemeral container and ss -lnt" q6
check_weighted 7 18 "(p6-core) probe reaches echo at its Pod IP on port 8080, with Cilium still in native routing" \
  "capture on both nodes; native routing means the Pod packets cross the nodes unchanged and are forwarded" q7
check_weighted 8 14 "(p6-core) lookup, on kbook-worker with dnsPolicy ClusterFirst, resolves echo.p6-core.svc.cluster.local to the Service IP" \
  "the DNS policy is part of the Pod spec: recreate the Pod" q8

echo
report_elapsed "${STATE}/start" "$EXAM_MINUTES"
KBOOK_PASS_PERCENT=$EXAM_PASS_PERCENT finish_checks
