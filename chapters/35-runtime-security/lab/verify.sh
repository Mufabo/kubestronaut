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

# jp <resource> <jsonpath>, in the lab's Namespace
jp() { kubectl -n "$LAB_NS" get "$1" -o "jsonpath=$2" 2>/dev/null; }

# audit_lines <nonce>: the audit log's lines that mention the nonce
audit_lines() { sudo grep -F -- "$1" "$AUDIT_LOG" 2>/dev/null; }
# audited_once <nonce> <level>: exactly one event, at that level
audited_once() {
  local out
  out="$(audit_lines "$1")"
  [[ -n "$out" && "$(wc -l <<<"$out")" -eq 1 && "$out" == *"\"level\":\"$2\""* ]]
}

t1() {
  local flags nonce
  flags="$(apiserver_flags)" || return 1
  for f in "--audit-policy-file=${AUDIT_POLICY}" "--audit-log-path=${AUDIT_LOG}" \
           --audit-log-maxage=7 --audit-log-maxbackup=2 --audit-log-maxsize=50; do
    grep -qxF -- "$f" <<<"$flags" || return 1
  done
  sudo test -f "$AUDIT_POLICY" || return 1
  # Requests for objects that do not exist, as a user without rights: refused,
  # but audited, and the random name finds them in the log.
  nonce="ch35-probe-$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  probe() { kubectl --as=ch35-auditor -n "$1" get "$2" "${nonce}-$2-$1" >/dev/null 2>&1; }
  probe "$LAB_NS" secret; probe default secret; probe "$LAB_NS" configmap
  probe "$LAB_NS" pod; probe default pod; probe "$LAB_NS" serviceaccount
  audited_once "${nonce}-secret-${LAB_NS}" Metadata || return 1
  audited_once "${nonce}-secret-default" Metadata || return 1
  audited_once "${nonce}-configmap-${LAB_NS}" Metadata || return 1
  audited_once "${nonce}-pod-${LAB_NS}" RequestResponse || return 1
  [[ -z "$(audit_lines "${nonce}-pod-default")" ]] || return 1
  [[ -z "$(audit_lines "${nonce}-serviceaccount-")" ]]
}

t2() {
  local bad name
  bad="$(cat "${STATE}/suspect" 2>/dev/null)"
  [[ -n "$bad" && -f "$FALCO_FILE" && "$(cat "$FALCO_FILE")" == "$bad" ]] || return 1
  [[ "$(jp "deployment/${bad}" '{.spec.replicas}/{.status.replicas}')" == "0/" ]] || return 1
  for name in "${SUSPECTS[@]}"; do
    [[ "$name" == "$bad" ]] && continue
    [[ "$(jp "deployment/${name}" '{.spec.replicas}/{.status.readyReplicas}')" == 1/1 ]] || return 1
  done
}

t3() {
  local since out
  on node1 "sudo grep -qx -- '- rule: Write below etc in container' ${FALCO_RULES}" || return 1
  falco_running || return 1
  since="$(on node1 'date +%s')" || return 1
  # Open /etc/group in the canary for appending, without writing anything to it.
  kubectl -n "$LAB_NS" exec canary -- sh -c ': >> /etc/group' >/dev/null 2>&1 || return 1
  # shellcheck disable=SC2329  # called through wait_for
  alerted() {
    out="$(on node1 "sudo journalctl -u ${FALCO_UNIT} --no-pager -o cat --since @${since}")"
    [[ "$out" == *"Warning"*"file=/etc/group"*"k8s_pod_name=canary"* ]]
  }
  # wait_for exits on timeout; in a subshell that is just a failed check.
  (wait_for "Falco's alert" 20 alerted) 2>/dev/null
}

t4() {
  local ro volumes pod out
  [[ "$(jp deployment/web '{.spec.replicas}/{.status.readyReplicas}/{.status.updatedReplicas}')" == 2/2/2 ]] || return 1
  [[ "$(jp deployment/web '{.spec.template.spec.containers[*].image}')" == nginx:1.27 ]] || return 1
  ro="$(jp deployment/web '{.spec.template.spec.containers[*].securityContext.readOnlyRootFilesystem}')"
  [[ "$ro" == true ]] || return 1
  # Every volume, if any, is an emptyDir.
  volumes="$(jp deployment/web '{range .spec.template.spec.volumes[*]}{.name}={.emptyDir}{"\n"}{end}')"
  [[ -z "$volumes" ]] || ! grep -q '=$' <<<"$volumes" || return 1
  pod="$(kubectl -n "$LAB_NS" get pods -l app=web --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
  [[ -n "$pod" ]] || return 1
  out="$(kubectl -n "$LAB_NS" exec "$pod" -- touch /usr/share/nginx/html/ch35-probe 2>&1)" && return 1
  [[ "$out" == *"Read-only file system"* ]]
}

t5() {
  local np
  [[ "$(jp pod/miner '{.metadata.uid}')" == "$(cat "${STATE}/miner-uid" 2>/dev/null)" ]] || return 1
  [[ "$(jp pod/miner '{.status.phase}/{.metadata.labels.status}')" == Running/quarantined ]] || return 1
  np="$(jp networkpolicy/quarantine '{.spec.podSelector.matchLabels}|{.spec.podSelector.matchExpressions}|{.spec.policyTypes}|{.spec.ingress}|{.spec.egress}')"
  [[ "$np" == '{"status":"quarantined"}||["Ingress","Egress"]||' || "$np" == '{"status":"quarantined"}||["Egress","Ingress"]||' ]]
}

check 1 "the API server writes an audit log at ${AUDIT_LOG} with the policy ${AUDIT_POLICY}: Secrets and ConfigMaps at Metadata, Pods in ${LAB_NS} at RequestResponse, nothing else" \
  "an audit Policy, the --audit-* flags, and volumes and mounts for the policy and the log in the API server's manifest" t1
check 2 "the Deployment whose Pod reads /etc/shadow is named in ${FALCO_FILE} and scaled to 0; the other two still run" \
  "on node1: sudo journalctl -u ${FALCO_UNIT} names the Pod (k8s_pod_name)" t2
check 3 "Falco's rule 'Write below etc in container' in ${FALCO_RULES} on node1 raises a Warning when a container opens a file below /etc for writing" \
  "the macros open_write and container exist; fd.name is the file; check the rule with journalctl -u ${FALCO_UNIT}" t3
check 4 "Deployment web runs 2 ready nginx:1.27 replicas with a read-only root file system, writing only to emptyDir volumes" \
  "securityContext.readOnlyRootFilesystem, and emptyDir volumes where nginx must write; kubectl logs shows where" t4
check 5 "Pod miner still runs (not recreated), labelled status=quarantined, and NetworkPolicy quarantine cuts all its traffic in and out" \
  "a NetworkPolicy that selects status=quarantined, with both policy types and no rules" t5

finish_checks
