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
file_is() { [[ -f "$1" ]] && [[ "$(tr -d '[:space:]' < "$1")" == "$2" ]]; }

t1() {
  [[ "$(kubectl get crd "$LAB_CRD" -o jsonpath='{.spec.group} {.spec.names.kind} {.spec.scope}' 2>/dev/null)" == "ch24.example.com Backup Namespaced" ]] &&
  [[ "$(kubectl get crd "$LAB_CRD" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null)" == True ]]
}

t2() {
  [[ "$(jp backup.ch24.example.com/nightly '{.spec.schedule}')" == "0 2 * * *" ]] &&
  [[ "$(jp backup.ch24.example.com/nightly '{.spec.target}')" == db ]]
}

t3() {
  # the schema must refuse a Backup without a target; the check asks the server itself
  local rejected=no
  kubectl -n "$LAB_NS" apply --dry-run=server -f - >/dev/null 2>&1 <<YAML || rejected=yes
apiVersion: ch24.example.com/v1
kind: Backup
metadata:
  name: bad-backup
spec:
  schedule: "0 2 * * *"
YAML
  [[ "$rejected" == yes ]] && file_is "$LAB_ANSWER_VALIDATION" rejected
}

t4() {
  local want
  want="$(k get backups.ch24.example.com -o name 2>/dev/null | tr -d '[:space:]')"
  [[ "$want" == "backup.ch24.example.com/nightly" ]] && [[ -f "$LAB_ANSWER_NAMES" ]] &&
  [[ "$(tr -d '[:space:]' < "$LAB_ANSWER_NAMES")" == "$want" ]]
}

t5() {
  local runtime
  runtime="$(kubectl get node "${CLUSTER_NAME}-worker" -o jsonpath='{.status.nodeInfo.containerRuntimeVersion}' 2>/dev/null)"
  runtime="${runtime%%://*}"
  [[ -n "$runtime" ]] && file_is "$LAB_ANSWER_CRI" "$runtime"
}

# Task 6: cert-manager installed with Helm, and a Certificate it issued
t6() {
  local release cert sys_leases own_leases
  command -v helm >/dev/null 2>&1 || return 1
  release="$(helm list -n "$CM_NS" -f "^${CM_RELEASE}\$" -o json 2>/dev/null)" &&
  [[ "$release" == *"\"chart\":\"cert-manager-${CERT_MANAGER_VERSION}\""* && "$release" == *'"status":"deployed"'* ]] &&
  sys_leases="$(kubectl -n kube-system get leases -o name 2>/dev/null)" &&
  own_leases="$(kubectl -n "$CM_NS" get leases -o name 2>/dev/null)" &&
  ! grep -q cert-manager <<<"$sys_leases" &&
  grep -q cert-manager <<<"$own_leases" &&
  [[ "$(jp issuer.cert-manager.io/selfsigned '{.spec.selfSigned}')" == "{}" ]] &&
  [[ "$(jp certificate.cert-manager.io/site '{.spec.secretName} {.spec.dnsNames[0]} {.spec.issuerRef.name}')" == "site-tls site.example.test selfsigned" ]] &&
  [[ "$(jp certificate.cert-manager.io/site '{.status.conditions[?(@.type=="Ready")].status}')" == True ]] &&
  [[ "$(jp secret/site-tls '{.type}')" == kubernetes.io/tls ]] &&
  # made by the operator, not by hand: cert-manager annotates the Secrets it issues
  [[ "$(jp secret/site-tls '{.metadata.annotations.cert-manager\.io/certificate-name}')" == site ]] &&
  cert="$(jp secret/site-tls '{.data.tls\.crt}' | base64 -d 2>/dev/null)" &&
  [[ "$(openssl x509 -noout -ext subjectAltName <<<"$cert" 2>/dev/null)" == *"DNS:site.example.test"* ]]
}

check 1 "CRD ${LAB_CRD}: group ch24.example.com, kind Backup, namespaced, and Established" \
  "kubectl apply the CRD, then kubectl wait --for=condition=Established" t1
check 2 "Backup nightly exists in ${LAB_NS} with schedule '0 2 * * *' and target db" \
  "a custom resource uses the CRD's group and version: apiVersion ch24.example.com/v1" t2
check 3 "The schema rejects a Backup without spec.target; ${LAB_ANSWER_VALIDATION} says rejected" \
  "kubectl apply --dry-run=server shows the validation error; use it to test the schema" t3
check 4 "${LAB_ANSWER_NAMES} lists the Backup objects by kind and name" \
  "kubectl get backups.ch24.example.com -o name" t4
check 5 "${LAB_ANSWER_CRI} names the container runtime of ${CLUSTER_NAME}-worker (the CRI)" \
  "the runtime is in .status.nodeInfo.containerRuntimeVersion, before the ://" t5

check 6 "Helm release cert-manager (${CERT_MANAGER_VERSION}) in ${CM_NS}, leases there; Certificate site (site.example.test, Issuer selfsigned) Ready, and the operator issued site-tls" \
  "--set crds.enabled=true --set global.leaderElection.namespace=${CM_NS}; then an Issuer with selfSigned: {} and a Certificate that names it" t6

finish_checks
