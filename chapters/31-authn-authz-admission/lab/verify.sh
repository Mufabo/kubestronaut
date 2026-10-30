#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

SA="system:serviceaccount:${LAB_NS}:ci-bot"
# can <verb> <resource> <namespace> [as]: the ci-bot ServiceAccount may do this
can() { [[ "$(kubectl auth can-i "$1" "$2" -n "$3" --as="$SA" 2>/dev/null)" == yes ]]; }

# deploy_yaml <name> <labelled yes|no>: a Deployment manifest, with or without a team label
deploy_yaml() {
  printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: %s\n' "$1"
  [[ "$2" == yes ]] && printf '  labels:\n    team: platform\n'
  printf 'spec:\n  replicas: 1\n  selector:\n    matchLabels:\n      app: %s\n' "$1"
  printf '  template:\n    metadata:\n      labels:\n        app: %s\n    spec:\n      containers:\n        - name: probe\n          image: nginx:1.27\n' "$1"
}

# pod_yaml <privileged yes|no>: a small Pod; "no" meets the restricted Pod Security level
pod_yaml() {
  printf 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: probe\nspec:\n'
  if [[ "$1" == yes ]]; then
    printf '  containers:\n    - name: probe\n      image: busybox:1.36\n      command: ["sleep", "3600"]\n      securityContext:\n        privileged: true\n'
  else
    printf '  securityContext:\n    runAsNonRoot: true\n    runAsUser: 1000\n    seccompProfile:\n      type: RuntimeDefault\n'
    printf '  containers:\n    - name: probe\n      image: busybox:1.36\n      command: ["sleep", "3600"]\n      securityContext:\n        allowPrivilegeEscalation: false\n        capabilities:\n          drop: ["ALL"]\n'
  fi
}

# dry_run <namespace> <manifest> [kubectl flags...]: server-side dry run. Sets DRY_OUT,
# returns the exit status. Admission runs, and nothing is stored.
dry_run() {
  local ns=$1 manifest=$2
  shift 2
  DRY_OUT="$(printf '%s\n' "$manifest" | kubectl -n "$ns" "$@" apply --dry-run=server -f - 2>&1)"
  local rc=$?
  return "$rc"
}

# whoami_with <token>: the username a token authenticates as, using its own kubeconfig
whoami_with() {
  local cfg
  cfg="$(mktemp)"
  kubectl config view --minify --raw > "$cfg" 2>/dev/null
  kubectl --kubeconfig "$cfg" config set-credentials ci-check --token="$1" >/dev/null 2>&1
  kubectl --kubeconfig "$cfg" --user=ci-check auth whoami -o jsonpath='{.status.userInfo.username}' 2>/dev/null
  rm -f "$cfg"
}

t1() {
  [[ "$(kubectl get validatingadmissionpolicy "$LAB_POLICY" -o name 2>/dev/null)" ]] || return 1
  [[ "$(kubectl get validatingadmissionpolicybinding "$LAB_BINDING" -o jsonpath='{.spec.policyName}' 2>/dev/null)" == "$LAB_POLICY" ]] || return 1
  [[ "$(kubectl get validatingadmissionpolicybinding "$LAB_BINDING" -o jsonpath='{.spec.validationActions}' 2>/dev/null)" == '["Deny"]' ]] || return 1
  [[ "$(kubectl get validatingadmissionpolicybinding "$LAB_BINDING" -o jsonpath='{.spec.matchResources.namespaceSelector.matchLabels.kubernetes\.io/metadata\.name}' 2>/dev/null)" == "$LAB_NS" ]] || return 1
  # Behaviour: rejected without the label in the bound Namespace, accepted with it,
  # and accepted without it in a Namespace the binding does not match.
  ! dry_run "$LAB_NS" "$(deploy_yaml probe-bare no)" && [[ "$DRY_OUT" == *"$LAB_POLICY"* ]] || return 1
  dry_run "$LAB_NS" "$(deploy_yaml probe-team yes)" || return 1
  dry_run "$LAB_PSA_NS" "$(deploy_yaml probe-bare no)"
}

t2() {
  [[ "$(kubectl get namespace "$LAB_PSA_NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)" == restricted ]] || return 1
  ! dry_run "$LAB_PSA_NS" "$(pod_yaml yes)" && [[ "$DRY_OUT" == *"violates PodSecurity"* ]] || return 1
  dry_run "$LAB_PSA_NS" "$(pod_yaml no)"
}

t3() {
  [[ -s "$LAB_TOKEN_FILE" ]] || return 1
  [[ "$(whoami_with "$(tr -d '[:space:]' < "$LAB_TOKEN_FILE")")" == "$SA" ]]
}

t4() {
  [[ "$(kubectl -n "$LAB_NS" get rolebinding ci-bot-deploys -o jsonpath='{.subjects[0].name}' 2>/dev/null)" == ci-bot ]] || return 1
  can create deployments.apps "$LAB_NS" && can get deployments.apps "$LAB_NS" &&
    can list deployments.apps "$LAB_NS" || return 1
  ! can delete deployments.apps "$LAB_NS" || return 1
  ! can create deployments.apps "$LAB_PSA_NS" || return 1
  # Authorization allows the request, and admission still applies the policy.
  ! dry_run "$LAB_NS" "$(deploy_yaml probe-bare no)" --as="$SA" && [[ "$DRY_OUT" == *"$LAB_POLICY"* ]] || return 1
  dry_run "$LAB_NS" "$(deploy_yaml probe-team yes)" --as="$SA"
}

check 1 "ValidatingAdmissionPolicy ${LAB_POLICY} requires a team label on Deployments, bound only in ${LAB_NS}" \
  "the binding needs validationActions Deny and a namespaceSelector for ${LAB_NS}; a Deployment without the label must be denied" t1
check 2 "Namespace ${LAB_PSA_NS} enforces the restricted Pod Security level" \
  "label the Namespace with pod-security.kubernetes.io/enforce=restricted; a privileged Pod must be refused by Pod Security" t2
check 3 "${LAB_TOKEN_FILE} holds a token that authenticates as ServiceAccount ci-bot" \
  "kubectl --token is ignored when the kubeconfig has a client certificate; a separate kubeconfig user avoids that" t3
check 4 "ServiceAccount ci-bot may create, get and list Deployments in ${LAB_NS} only, and admission still applies" \
  "a Role deployer and a RoleBinding ci-bot-deploys; a Deployment without the team label is refused even when RBAC allows it" t4

finish_checks
