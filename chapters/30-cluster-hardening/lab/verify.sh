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

t1() {
  local out fails
  out="$(ssh node2 'sudo kube-bench run --targets node --benchmark cis-1.12 2>/dev/null')" || return 1
  fails="$(grep -E '^[0-9]+ checks FAIL$' <<<"$out")"
  [[ -n "$fails" ]] || return 1
  ! grep -qvE '^0 checks FAIL$' <<<"$fails"
}

t2() {
  local c
  for c in "${COMPONENTS[@]}"; do profiling_off "$c" || return 1; done
}

t3() {
  local cfg
  cfg="$(kubelet_configz node1)"
  [[ "$cfg" == *'"anonymous":{"enabled":false}'* && "$cfg" == *'"authorization":{"mode":"Webhook"'* ]] || return 1
  ! grep -qE '"readOnlyPort":[1-9]' <<<"$cfg" || return 1
  [[ "$(curl -sk -m 5 https://node1:10250/pods)" == Unauthorized ]] || return 1
  ! curl -s -m 3 -o /dev/null http://node1:10255/healthz || return 1
  node_ready node1
}

t4() {
  local files want
  files="$(ls -A "$BIN_DIR" 2>/dev/null)"
  want="$(cat "${STATE}/genuine" 2>/dev/null)"
  [[ -n "$want" && "$files" == "$want" ]] || return 1
  [[ "$(sha512sum "${BIN_DIR}/${want}" 2>/dev/null | cut -d' ' -f1)" == "$(cat "${STATE}/genuine.sha512")" ]]
}

t5() {
  local jp='{.spec.podSelector}|{.spec.policyTypes[*]}|{.spec.egress[*].to[*].ipBlock.cidr}|{.spec.egress[*].to[*].ipBlock.except[*]}'
  [[ "$(kubectl -n "$LAB_NS" get networkpolicy deny-metadata -o "jsonpath=${jp}" 2>/dev/null)" == '{}|Egress|0.0.0.0/0|169.254.169.254/32' ]] || return 1
  kubectl -n "$LAB_NS" exec client -- wget -qO- -T 3 http://web >/dev/null 2>&1
}

check 1 "kube-bench's node checks (cis-1.12) on node2 report no FAIL" \
  "ssh node2, run kube-bench with --targets node --benchmark cis-1.12, and read the audit of each FAIL (--json shows it)" t1
check 2 "The API server, controller manager, and scheduler run with --profiling=false and are ready" \
  "add - --profiling=false to the command of each manifest in ${MANIFESTS}" t2
check 3 "node1's kubelet: anonymous authentication off, authorization Webhook, read-only port off; it rejects anonymous requests and is Ready" \
  "edit ${KUBELET_CONFIG} on node1, then sudo systemctl restart kubelet" t3
check 4 "${BIN_DIR} holds only the kubectl that matches the published SHA-512 of kubectl ${K8S_VERSION}" \
  "curl the .sha512 from dl.k8s.io for ${K8S_VERSION} linux/amd64 and compare it with sha512sum of each file" t4
check 5 "NetworkPolicy deny-metadata in ${LAB_NS} denies only 169.254.169.254/32 for egress, and client still reaches web" \
  "podSelector: {}, policyTypes: [Egress], egress to an ipBlock 0.0.0.0/0 with except" t5

finish_checks
