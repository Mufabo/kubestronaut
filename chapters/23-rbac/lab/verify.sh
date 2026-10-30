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
SA="system:serviceaccount:${LAB_NS}:reporter"
# can <verb> <resource> [namespace-flag...]: the reporter ServiceAccount may do this
can() { [[ "$(kubectl auth can-i "$1" "$2" --as="$SA" "${@:3}" 2>/dev/null)" == yes ]]; }
# pod_api <path> <method>: the probe Pod's HTTP status code for a request to the API
pod_api() {
  k exec probe -- sh -c "curl -s -o /dev/null -w '%{http_code}' --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -X $2 -H \"Authorization: Bearer \$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)\" https://kubernetes.default.svc$1" 2>/dev/null
}

t1() {
  can list pods -n "$LAB_NS" && can get pods -n "$LAB_NS" &&
  ! can delete pods -n "$LAB_NS" &&
  [[ "$(jp role/pod-reader '{.rules[0].verbs}')" == '["get","list"]' ]] &&
  [[ "$(jp rolebinding/reporter-reads-pods '{.subjects[0].name}')" == reporter ]]
}

t2() {
  can list nodes &&
  [[ "$(kubectl get clusterrole "$LAB_CLUSTERROLE" -o jsonpath='{.rules[0].resources[0]}' 2>/dev/null)" == nodes ]] &&
  [[ "$(kubectl get clusterrolebinding "$LAB_CLUSTERROLEBINDING" -o jsonpath='{.subjects[0].name}' 2>/dev/null)" == reporter ]]
}

t3() {
  [[ "$(jp pod/probe '{.spec.serviceAccountName}')" == reporter ]] &&
  [[ "$(pod_api "/api/v1/namespaces/${LAB_NS}/pods" GET)" == 200 ]] &&
  [[ "$(pod_api "/api/v1/namespaces/${LAB_NS}/pods/probe" DELETE)" == 403 ]]
}

t4() {
  [[ "$(jp serviceaccount/builder '{.automountServiceAccountToken}')" == false ]] &&
  [[ "$(jp pod/quiet '{.spec.serviceAccountName}')" == builder ]] &&
  ! k exec quiet -- test -e /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null
}

t5() {
  local want
  want="$(kubectl auth can-i delete pods --as="$SA" -n "$LAB_NS" 2>/dev/null)"
  [[ -n "$want" && -f "$LAB_ANSWER_CAN_DELETE" ]] || return 1
  [[ "$(tr -d '[:space:]' < "$LAB_ANSWER_CAN_DELETE")" == "$want" ]]
}

check 1 "ServiceAccount reporter may list and get pods in ${LAB_NS} through Role pod-reader, but not delete them" \
  "a Role with verbs get and list, and a RoleBinding to system:serviceaccount:${LAB_NS}:reporter" t1
check 2 "ServiceAccount reporter may list nodes through ClusterRole ${LAB_CLUSTERROLE}" \
  "a ClusterRole is cluster-scoped; its binding is a ClusterRoleBinding" t2
check 3 "Pod probe runs as reporter and its token lists pods (200) but cannot delete one (403)" \
  "the curl image reads /var/run/secrets/kubernetes.io/serviceaccount/token and the CA" t3
check 4 "ServiceAccount builder disables token automount; Pod quiet has no API token" \
  "automountServiceAccountToken is a field of the ServiceAccount, and also of the Pod" t4
check 5 "${LAB_ANSWER_CAN_DELETE} holds the answer of kubectl auth can-i delete pods for reporter" \
  "kubectl auth can-i VERB RESOURCE --as=system:serviceaccount:NS:NAME -n NS" t5

finish_checks
