#!/usr/bin/env bash
# Automated reference solution (used by CI). Human-readable version: solutions.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

# Task 1 and Task 2: one policy, with one validation per rule, and a binding to the Namespace.
kubectl apply -f - >/dev/null <<YAML
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: ${LAB_POLICY}
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
  validations:
    - expression: "object.spec.containers.all(c, c.image.startsWith('registry.kbook.example/')) && (!has(object.spec.initContainers) || object.spec.initContainers.all(c, c.image.startsWith('registry.kbook.example/')))"
      message: "Images must come from registry.kbook.example"
    - expression: "object.spec.containers.all(c, c.image.contains('@sha256:')) && (!has(object.spec.initContainers) || object.spec.initContainers.all(c, c.image.contains('@sha256:')))"
      message: "Images must be pinned by digest"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: ${LAB_BINDING}
spec:
  policyName: ${LAB_POLICY}
  validationActions: ["Deny"]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: ${LAB_NS}
YAML

# Task 3
id="$(kubectl -n "$LAB_NS" get pod runner -o jsonpath='{.status.containerStatuses[0].imageID}')"
printf '%s\n' "${id##*@}" > "$LAB_DIGEST_FILE"

# Task 4: no host network, no privileged mode, a non-root user, a read-only root
# file system, and the restricted settings.
kubectl -n "$LAB_SCAN_NS" patch deployment report --type=strategic -p '{"spec":{"template":{"spec":{
  "hostNetwork":false,
  "securityContext":{"runAsNonRoot":true,"runAsUser":10001,"runAsGroup":10001,"seccompProfile":{"type":"RuntimeDefault"}},
  "containers":[{"name":"report","securityContext":{"privileged":false,"allowPrivilegeEscalation":false,
    "readOnlyRootFilesystem":true,"capabilities":{"drop":["ALL"]}}}]}}}}' >/dev/null

# Task 5: scan each Pod's image; delete the Pods whose image has a CRITICAL vulnerability.
: > "$LAB_CRITICAL_FILE"
while read -r pod image; do
  if ! trivy image --quiet --skip-db-update --severity CRITICAL --exit-code 1 "$image" >/dev/null 2>&1 </dev/null; then
    printf '%s\n' "$pod" >> "$LAB_CRITICAL_FILE"
  fi
done < "${here}/.state/scan-images"
sort -o "$LAB_CRITICAL_FILE" "$LAB_CRITICAL_FILE"
while read -r pod; do
  kubectl -n "$LAB_SCAN_NS" delete pod "$pod" --wait=true >/dev/null </dev/null
done < "$LAB_CRITICAL_FILE"

# Task 6: a key pair without a password, and a signature that stays out of the
# public transparency log.
COSIGN_PASSWORD='' cosign generate-key-pair --output-key-prefix "${LAB_COSIGN_KEY%.key}" >/dev/null 2>&1
COSIGN_PASSWORD='' cosign sign --yes --key "$LAB_COSIGN_KEY" --use-signing-config=false --tlog-upload=false \
  "${LAB_REGISTRY}/ch34/app:1.0" >/dev/null 2>&1

kubectl -n "$LAB_SCAN_NS" rollout status deployment/report --timeout=180s >/dev/null
# rollout status returns while old Pods still terminate; wait until only the new ones are left.
two_report_pods() { [[ "$(kubectl -n "$LAB_SCAN_NS" get pods -l app=report -o name | wc -l)" -eq 2 ]]; }
wait_for "old report Pods to terminate" 120 two_report_pods
