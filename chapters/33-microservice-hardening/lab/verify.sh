#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_snapshot "$LAB_SNAPSHOT"
require_lab_cluster

# jp <namespace> <resource> <jsonpath>
jp() { kubectl -n "$1" get "$2" -o "jsonpath=$3" 2>/dev/null; }
# running <namespace> <pod>: the Pod is Running and every container is ready
running() {
  local r
  r="$(jp "$1" "pod/$2" '{.status.containerStatuses[*].ready}')" || return 1
  [[ "$(jp "$1" "pod/$2" '{.status.phase}')" == Running && -n "$r" && "$r" != *false* ]]
}

t1() {
  [[ -f "$VIOLATIONS_FILE" && "$(cat "$VIOLATIONS_FILE")" == $'backup\ndebugger\nmetrics' ]] || return 1
  [[ "$(kubectl get namespace ch33-legacy -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}/{.metadata.labels.pod-security\.kubernetes\.io/warn}' 2>/dev/null)" == baseline/restricted ]]
}

t2() {
  [[ "$(kubectl get namespace ch33-apps -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)" == restricted ]] || return 1
  [[ "$(jp ch33-apps deployment/worker '{.spec.replicas}/{.status.readyReplicas}')" == 2/2 ]]
}

t3() {
  local vol
  running ch33-apps api || return 1
  [[ "$(jp ch33-apps pod/api '{.spec.containers[0].image}')" == busybox:1.36 ]] || return 1
  vol="$(jp ch33-apps pod/api '{.spec.volumes[?(@.secret.secretName=="db-pass")].name}')"
  [[ -n "$vol" && "$vol" != *" "* ]] || return 1
  [[ "$(jp ch33-apps pod/api "{.spec.containers[0].volumeMounts[?(@.name==\"${vol}\")].mountPath}")" == /etc/db ]] || return 1
  [[ "$(kubectl -n ch33-apps exec api -- stat -L -c %a /etc/db/password 2>/dev/null)" == 400 ]] || return 1
  [[ -z "$(jp ch33-apps pod/api '{.spec.containers[*].env[*].valueFrom.secretKeyRef.name}{.spec.containers[*].envFrom[*].secretRef.name}')" ]] || return 1
  [[ -z "$(jp ch33-apps pod/api '{.spec.volumes[*].projected.sources[*].serviceAccountToken.path}')" ]]
}

t4() {
  sudo test -f "$ENC_CONFIG" || return 1
  [[ "$(etcd_prefix /registry/secrets/ch33-apps/db-pass)" == "k8s:enc:aescbc:v1:key1:" ]] || return 1
  [[ "$(jp ch33-apps secret/db-pass '{.data.password}' | base64 -d 2>/dev/null)" == "$(cat "${STATE}/db-pass" 2>/dev/null)" ]]
}

t5() {
  [[ "$(kubectl get runtimeclass gvisor -o jsonpath='{.handler}' 2>/dev/null)" == runsc ]] || return 1
  [[ "$(jp ch33-sandbox pod/sandboxed '{.spec.runtimeClassName}/{.spec.containers[0].image}')" == gvisor/busybox:1.36 ]] || return 1
  running ch33-sandbox sandboxed || return 1
  [[ "$(kubectl -n ch33-sandbox exec sandboxed -- uname -r 2>/dev/null)" == *gvisor ]]
}

check 1 "${VIOLATIONS_FILE} lists the Pods of ch33-legacy that break baseline; the Namespace enforces baseline and warns about restricted" \
  "kubectl label --dry-run=server --overwrite namespace ch33-legacy pod-security.kubernetes.io/enforce=baseline" t1
check 2 "Deployment worker in ch33-apps has 2 ready replicas, and the Namespace still enforces restricted" \
  "kubectl -n ch33-apps get events --field-selector reason=FailedCreate lists the fields restricted needs" t2
check 3 "Pod api in ch33-apps runs, with db-pass mounted at /etc/db in mode 0400, no Secret in its environment, and no ServiceAccount token" \
  "a secret volume with defaultMode: 0400, automountServiceAccountToken: false, and the restricted securityContext" t3
check 4 "Secret db-pass is stored in etcd with the prefix k8s:enc:aescbc:v1:key1:, and the API returns its original value" \
  "an EncryptionConfiguration in ${ENC_CONFIG}, the flag, volume, and mount in the API server's manifest, then rewrite the Secrets" t4
check 5 "RuntimeClass gvisor (handler runsc); Pod sandboxed in ch33-sandbox runs on it, with gVisor's kernel" \
  "runtimeClassName: gvisor in the Pod spec; check with uname -r" t5

finish_checks
