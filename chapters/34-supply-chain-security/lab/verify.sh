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
TRUSTED="registry.kbook.example"
DIGEST="sha256:$(printf 'a%.0s' {1..64})"

# pod_yaml <container image> [init image]: a small Pod with one container, and an init
# container when given
pod_yaml() {
  printf 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: probe\nspec:\n'
  [[ -n "${2:-}" ]] && printf '  initContainers:\n    - name: init\n      image: %s\n      command: ["true"]\n' "$2"
  printf '  containers:\n    - name: app\n      image: %s\n      command: ["sleep", "3600"]\n' "$1"
}

# dry_run <manifest>: a server-side dry run in the lab Namespace. Admission runs, nothing is
# stored. Sets DRY_OUT and returns the exit status.
dry_run() {
  DRY_OUT="$(printf '%s\n' "$1" | k apply --dry-run=server -f - 2>&1)"
}

t1() {
  [[ "$(kubectl get validatingadmissionpolicybinding "$LAB_BINDING" -o jsonpath='{.spec.policyName}' 2>/dev/null)" == "$LAB_POLICY" ]] || return 1
  [[ "$(kubectl get validatingadmissionpolicybinding "$LAB_BINDING" -o jsonpath='{.spec.validationActions}' 2>/dev/null)" == '["Deny"]' ]] || return 1
  [[ "$(kubectl get validatingadmissionpolicybinding "$LAB_BINDING" -o jsonpath='{.spec.matchResources.namespaceSelector.matchLabels.kubernetes\.io/metadata\.name}' 2>/dev/null)" == "$LAB_NS" ]] || return 1
  # Accepted: a digest-pinned image from the trusted registry, as a container and as an init container.
  dry_run "$(pod_yaml "${TRUSTED}/app@${DIGEST}" "${TRUSTED}/init@${DIGEST}")" || return 1
  # Refused: a Docker Hub image, as a container, and as an init container of a trusted one.
  ! dry_run "$(pod_yaml "nginx:1.27")" && [[ "$DRY_OUT" == *"$LAB_POLICY"* ]] || return 1
  ! dry_run "$(pod_yaml "${TRUSTED}/app@${DIGEST}" "busybox:1.36")" && [[ "$DRY_OUT" == *"$LAB_POLICY"* ]]
}

t2() {
  # Accepted: a trusted image pinned by digest. Refused: the same image with only a tag,
  # as a container and as an init container.
  dry_run "$(pod_yaml "${TRUSTED}/app@${DIGEST}" "${TRUSTED}/init@${DIGEST}")" || return 1
  ! dry_run "$(pod_yaml "${TRUSTED}/app:1.0")" && [[ "$DRY_OUT" == *"$LAB_POLICY"* ]] || return 1
  ! dry_run "$(pod_yaml "${TRUSTED}/app@${DIGEST}" "${TRUSTED}/init:1.0")" && [[ "$DRY_OUT" == *"$LAB_POLICY"* ]]
}

t3() {
  local id digest
  id="$(jp pod/runner '{.status.containerStatuses[0].imageID}')"
  digest="${id##*@}"
  [[ -n "$digest" && "$digest" == sha256:* ]] || return 1
  [[ -f "$LAB_DIGEST_FILE" ]] || return 1
  [[ "$(tr -d '[:space:]' < "$LAB_DIGEST_FILE")" == "$digest" ]]
}

t4() {
  local tmp rc
  [[ "$(kubectl -n "$LAB_SCAN_NS" get deployment report -o jsonpath='{.spec.replicas}/{.status.readyReplicas}/{.status.updatedReplicas}/{.status.replicas}' 2>/dev/null)" == 2/2/2/2 ]] || return 1
  [[ "$(kubectl -n "$LAB_SCAN_NS" get deployment report -o jsonpath='{.spec.template.spec.containers[*].image}' 2>/dev/null)" == busybox:1.36 ]] || return 1
  # Scan the live object, as the cluster has it.
  tmp="$(mktemp -d)"
  kubectl -n "$LAB_SCAN_NS" get deployment report -o yaml > "${tmp}/report.yaml" 2>/dev/null
  trivy config --quiet --severity HIGH,CRITICAL --exit-code 1 "${tmp}/report.yaml" >/dev/null 2>&1
  rc=$?
  rm -rf "$tmp"
  return "$rc"
}

# critical_pods: the Pods labelled scan=me whose image has a CRITICAL vulnerability,
# sorted, by the vulnerability database the reader's scans used.
critical_pods() {
  local pod image count
  while read -r pod image; do
    count="$(trivy image --quiet --skip-db-update --severity CRITICAL --format template \
      --template '{{range .}}{{range .Vulnerabilities}}x{{end}}{{end}}' "$image" 2>/dev/null </dev/null)" || return 1
    if [[ -n "$count" ]]; then printf '%s\n' "$pod"; fi
  done < "${here}/.state/scan-images"
}

t5() {
  local expected pod image
  [[ -s "${here}/.state/scan-images" && -f "$LAB_CRITICAL_FILE" ]] || return 1
  expected="$(critical_pods | LC_ALL=C sort)" || return 1
  [[ -n "$expected" && "$(cat "$LAB_CRITICAL_FILE")" == "$expected" ]] || return 1
  while read -r pod image; do
    if grep -qx "$pod" <<<"$expected"; then
      ! kubectl -n "$LAB_SCAN_NS" get pod "$pod" >/dev/null 2>&1 </dev/null || return 1
    else
      [[ "$(kubectl -n "$LAB_SCAN_NS" get pod "$pod" -o jsonpath='{.spec.containers[0].image}/{.status.phase}' 2>/dev/null </dev/null)" == "${image}/Running" ]] || return 1
    fi
  done < "${here}/.state/scan-images"
}

t6() {
  [[ -f "$LAB_COSIGN_KEY" && -f "$LAB_COSIGN_PUB" ]] || return 1
  cosign verify --key "$LAB_COSIGN_PUB" --insecure-ignore-tlog=true "${LAB_REGISTRY}/ch34/app:1.0" >/dev/null 2>&1 || return 1
  ! cosign verify --key "$LAB_COSIGN_PUB" --insecure-ignore-tlog=true "${LAB_REGISTRY}/ch34/app:1.1" >/dev/null 2>&1
}

check 1 "ValidatingAdmissionPolicy ${LAB_POLICY} accepts only images from ${TRUSTED}, in containers and init containers, bound to ${LAB_NS}" \
  "the binding needs validationActions Deny and a namespaceSelector for ${LAB_NS}; a Docker Hub image must be refused" t1
check 2 "The policy also refuses trusted images that are not pinned by digest, in containers and init containers" \
  "a digest reference contains @sha256:; a tag such as :1.0 does not pin the image" t2
check 3 "${LAB_DIGEST_FILE} holds the digest of the image Pod runner runs" \
  "the digest is the part of the imageID after @, in pod status" t3
check 4 "Deployment report in ${LAB_SCAN_NS} runs 2 ready busybox:1.36 replicas, and trivy config finds no HIGH or CRITICAL misconfiguration in it" \
  "kubectl get deployment report -o yaml > report.yaml; trivy config --severity HIGH,CRITICAL report.yaml lists what to change" t4
check 5 "The Pods labelled scan=me whose image has a CRITICAL vulnerability are deleted and listed in ${LAB_CRITICAL_FILE}; the others still run" \
  "trivy image --severity CRITICAL IMAGE for each Pod's image" t5
check 6 "${LAB_REGISTRY}/ch34/app:1.0 is signed with the key pair ${LAB_COSIGN_KEY} / ${LAB_COSIGN_PUB}, and app:1.1 is not" \
  "cosign generate-key-pair, then cosign sign --key; check with cosign verify --key --insecure-ignore-tlog=true" t6

finish_checks
