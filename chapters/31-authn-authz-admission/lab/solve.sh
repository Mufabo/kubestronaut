#!/usr/bin/env bash
# Automated reference solution (used by CI). Human-readable version: solutions.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

k() { kubectl -n "$LAB_NS" "$@"; }

# Task 1
kubectl apply -f - >/dev/null <<YAML
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: ${LAB_POLICY}
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["deployments"]
  validations:
    - expression: "has(object.metadata.labels) && 'team' in object.metadata.labels"
      message: "Deployments need a team label"
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

# Task 2
kubectl label namespace "$LAB_PSA_NS" pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null

# Task 3
kubectl -n "$LAB_NS" create token ci-bot --duration=1h > "$LAB_TOKEN_FILE"

# Task 4
k create role deployer --verb=create,get,list --resource=deployments.apps >/dev/null
k create rolebinding ci-bot-deploys --role=deployer --serviceaccount="${LAB_NS}:ci-bot" >/dev/null
