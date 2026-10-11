#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

k() { kubectl -n "$LAB_NS" "$@"; }
jp() { k get "$1" -o "jsonpath=$2" 2>/dev/null; }
cjp() { kubectl "$1" -o "jsonpath=$2" 2>/dev/null; }
# reaches <pod> <url>: the request succeeds within 3 seconds
reaches() { k exec "$1" -- wget -T 3 -qO- "$2" >/dev/null 2>&1; }
BACKEND_URL="http://backend.${LAB_NS}.svc.cluster.local"

t1() {
  local want got
  want="$(kubectl get node "${CLUSTER_NAME}-worker" -o jsonpath='{.spec.podCIDR}' 2>/dev/null)" || return 1
  [[ -n "$want" && -f "$LAB_ANSWER_CIDR" ]] || return 1
  got="$(tr -d '[:space:]' < "$LAB_ANSWER_CIDR")"
  [[ "$got" == "$want" ]]
}

t2() {
  local ip
  ip="$(jp svc/backend '{.spec.clusterIP}')"
  [[ -n "$ip" && -f "$LAB_ANSWER_IP" ]] || return 1
  [[ "$(tr -d '[:space:]' < "$LAB_ANSWER_IP")" == "$ip" ]]
}

t3() {
  # the default-deny policy: no ingress is allowed to the backend Pods...
  [[ "$(jp networkpolicy/deny-all '{.spec.podSelector}')" == "{}" ]] &&
  [[ "$(jp networkpolicy/deny-all '{.spec.policyTypes[0]}')" == Ingress ]] || return 1
  # ...so the intruder, which no other policy allows, is blocked
  ! reaches intruder "$BACKEND_URL"
}

t4() {
  [[ "$(jp networkpolicy/allow-client '{.spec.podSelector.matchLabels.app}')" == backend ]] ||
  [[ "$(jp networkpolicy/allow-client '{.spec.podSelector.matchLabels.tier}')" == api ]] || return 1
  [[ "$(jp networkpolicy/allow-client '{.spec.ingress[0].from[0].podSelector.matchLabels.app}')" == client ]] || return 1
  [[ "$(jp networkpolicy/allow-client '{.spec.ingress[0].ports[0].port}')" == 80 ]] || return 1
  reaches client "$BACKEND_URL"
}

t5() {
  local want got
  want="$(kubectl -n kube-system get configmap kube-proxy -o jsonpath='{.data.config\.conf}' 2>/dev/null | sed -n 's/^mode: *"\{0,1\}\([a-z]*\)"\{0,1\}$/\1/p' | head -1)"
  [[ -n "$want" && -f "$LAB_ANSWER_PROXY" ]] || return 1
  got="$(tr -d '[:space:]' < "$LAB_ANSWER_PROXY")"
  [[ "$got" == "$want" ]]
}

check 1 "File $LAB_ANSWER_CIDR holds the pod CIDR of node ${CLUSTER_NAME}-worker" \
  "kubectl get node NAME -o jsonpath='{.spec.podCIDR}'" t1
check 2 "File $LAB_ANSWER_IP holds the ClusterIP of Service backend, which CoreDNS returns for its name" \
  "nslookup backend from the client Pod, or read the Service's .spec.clusterIP" t2
check 3 "NetworkPolicy deny-all selects every Pod and denies ingress; the intruder cannot reach backend" \
  "a policy with podSelector {} and policyTypes [Ingress] is a default deny" t3
check 4 "NetworkPolicy allow-client lets app=client reach backend on port 80" \
  "the from and ports fields sit under spec.ingress[0]" t4
check 5 "File $LAB_ANSWER_PROXY holds the kube-proxy mode from its ConfigMap" \
  "kubectl -n kube-system get configmap kube-proxy -o yaml, look for mode:" t5

finish_checks
