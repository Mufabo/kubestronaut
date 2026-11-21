#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

ns=$LAB_NS
# in_cidrs <ip> <cidr>...   the address is inside one of the ranges
in_cidrs() {
  python3 -c 'import ipaddress,sys; ip=ipaddress.ip_address(sys.argv[1]); sys.exit(not any(ip in ipaddress.ip_network(c) for c in sys.argv[2:]))' "$@" 2>/dev/null
}
pool_cidrs() { kubectl get ciliumpodippool "$1" -o jsonpath='{.spec.ipv4.cidrs[*]}' 2>/dev/null; }
pool_mask() { kubectl get ciliumpodippool "$1" -o jsonpath='{.spec.ipv4.maskSize}' 2>/dev/null; }
# pod_ips <namespace> <app>   the addresses of the Running Pods with label app=<app>
pod_ips() {
  kubectl -n "$1" get pods -l "app=$2" --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' 2>/dev/null
}
ready_replicas() { kubectl -n "$1" get deployment "$2" -o jsonpath='{.status.readyReplicas}' 2>/dev/null; }
all_in() { # all_in <namespace> <app> <want-count> <cidr>...
  local ns=$1 app=$2 want=$3 ips ip n=0; shift 3
  ips="$(pod_ips "$ns" "$app")"
  for ip in $ips; do in_cidrs "$ip" "$@" || return 1; n=$((n + 1)); done
  ((n == want))
}
# reaches <ip>   client gets an HTTP answer from <ip>:8080 that shows client's own address
reaches() {
  local body cip
  cip="$(pod_ip "$ns" client)"
  body="$(kubectl -n "$ns" exec client -- curl -s --max-time 3 "http://$1:8080/clientip" 2>/dev/null)"
  [[ -n "$cip" && "${body%:*}" == "$cip" ]]
}

t1() {
  local cidr podcidr
  cidr="$(docker exec kbook-control-plane cat /etc/kubernetes/manifests/kube-controller-manager.yaml 2>/dev/null |
    sed -n 's/.*--cluster-cidr=\([^ ]*\).*/\1/p' | head -n1)"
  podcidr="$(kubectl get node kbook-worker -o jsonpath='{.spec.podCIDR}' 2>/dev/null)"
  [[ -n "$cidr" && -n "$podcidr" ]] &&
    answer_is "${LAB_ANSWERS}/cluster-cidr" "$cidr" &&
    answer_is "${LAB_ANSWERS}/node-addresses" "$((1 << (32 - ${podcidr#*/})))"
}
t2() {
  local ip
  [[ "$(pool_cidrs blue)" == 10.20.0.0/16 && "$(pool_mask blue)" == 28 ]] &&
    [[ "$(ready_replicas ch50-blue api)" == 3 ]] && all_in ch50-blue api 3 10.20.0.0/16 &&
    ip="$(pod_ips ch50-blue api | head -n1)" && reaches "$ip"
}
# shellcheck disable=SC2086  # CIDR lists are meant to be split
t3() {
  local cidrs c
  cidrs="$(pool_cidrs small)"
  [[ " $cidrs " == *" 10.30.0.0/27 "* && "$(pool_mask small)" == 28 ]] || return 1
  for c in $cidrs; do
    python3 -c 'import ipaddress,sys; sys.exit(not ipaddress.ip_network(sys.argv[1]).subnet_of(ipaddress.ip_network("10.30.0.0/16")))' "$c" 2>/dev/null || return 1
  done
  [[ "$(kubectl -n ch50-batch get deployment batch -o jsonpath='{.spec.replicas}' 2>/dev/null)" == 40 &&
     "$(kubectl get namespace ch50-batch -o jsonpath='{.metadata.annotations.ipam\.cilium\.io/ip-pool}' 2>/dev/null)" == small &&
     "$(ready_replicas ch50-batch batch)" == 40 ]] &&
    all_in ch50-batch batch 40 $cidrs
}
# shellcheck disable=SC2086  # CIDR lists are meant to be split
t4() {
  local ip blue
  blue="$(pool_cidrs blue)"
  ip="$(pod_ip "$ns" metrics)"
  pod_phase_is "$ns" metrics Running && [[ -n "$ip" && -n "$blue" ]] &&
    in_cidrs "$ip" $blue &&
    [[ -z "$(kubectl get namespace "$ns" -o jsonpath='{.metadata.annotations.ipam\.cilium\.io/ip-pool}' 2>/dev/null)" ]] &&
    in_cidrs "$(pod_ip "$ns" client)" 10.10.0.0/16 && reaches "$ip"
}

check 1 "${LAB_ANSWERS}/cluster-cidr holds the controller manager's cluster CIDR, and ${LAB_ANSWERS}/node-addresses the number of addresses in kbook-worker's podCIDR" \
  "Read the flags in /etc/kubernetes/manifests/kube-controller-manager.yaml on the control plane node, and kubectl get node kbook-worker -o jsonpath='{.spec.podCIDR}'" t1
check 2 "pool blue (10.20.0.0/16, /28 blocks) exists; the 3 api Pods in ch50-blue run with addresses from it, and client reaches them" \
  "kubectl -n ch50-blue describe pod shows why the Pods wait; create the CiliumPodIPPool (apiVersion cilium.io/v2alpha1) that the namespace asks for" t2
check 3 "all 40 batch Pods in ch50-batch run with addresses from pool small, which still holds 10.30.0.0/27 and only ranges inside 10.30.0.0/16 (Deployment and annotation unchanged)" \
  "The pool is exhausted: add a second range from 10.30.0.0/16 to spec.ipv4.cidrs of CiliumPodIPPool small" t3
check 4 "Pod metrics in ch50-ipam runs with an address from pool blue, client reaches it on port 8080, and the namespace itself stays on the default pool" \
  "A Pod can choose its own pool with the annotation ipam.cilium.io/ip-pool" t4
finish_checks
