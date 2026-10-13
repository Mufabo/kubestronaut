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

check 1 "ValidatingAdmissionPolicy ${LAB_POLICY} accepts only images from ${TRUSTED}, in containers and init containers, bound to ${LAB_NS}" \
  "the binding needs validationActions Deny and a namespaceSelector for ${LAB_NS}; a Docker Hub image must be refused" t1
check 2 "The policy also refuses trusted images that are not pinned by digest, in containers and init containers" \
  "a digest reference contains @sha256:; a tag such as :1.0 does not pin the image" t2
check 3 "${LAB_DIGEST_FILE} holds the digest of the image Pod runner runs" \
  "the digest is the part of the imageID after @, in pod status" t3

finish_checks
