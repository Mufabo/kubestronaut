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
