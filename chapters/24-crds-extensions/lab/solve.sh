#!/usr/bin/env bash
# Automated reference solution (used by CI). Human-readable version: solutions.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

# Task 1
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.ch24.example.com
spec:
  group: ch24.example.com
  scope: Namespaced
  names:
    plural: backups
    singular: backup
    kind: Backup
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required: [schedule, target]
              properties:
                schedule:
                  type: string
                target:
                  type: string
YAML
kubectl wait --for=condition=Established "crd/${LAB_CRD}" --timeout=120s >/dev/null

# Task 2
kubectl -n "$LAB_NS" apply -f - >/dev/null <<'YAML'
apiVersion: ch24.example.com/v1
kind: Backup
metadata:
  name: nightly
spec:
  schedule: "0 2 * * *"
  target: db
YAML

# Task 3: the server refuses the object, so the reader records the refusal
if kubectl -n "$LAB_NS" apply --dry-run=server -f - >/dev/null 2>&1 <<'YAML'
apiVersion: ch24.example.com/v1
kind: Backup
metadata:
  name: bad-backup
spec:
  schedule: "0 2 * * *"
YAML
then
  echo accepted > "$LAB_ANSWER_VALIDATION"
else
  echo rejected > "$LAB_ANSWER_VALIDATION"
fi

# Task 4
kubectl -n "$LAB_NS" get backups.ch24.example.com -o name > "$LAB_ANSWER_NAMES"

# Task 5: the runtime name is the part before :// in the node's runtime version
kubectl get node "${CLUSTER_NAME}-worker" -o jsonpath='{.status.nodeInfo.containerRuntimeVersion}' | sed 's#://.*##' > "$LAB_ANSWER_CRI"

# Task 6: the operator first, then what it should manage
helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
helm install "$CM_RELEASE" jetstack/cert-manager --version "$CERT_MANAGER_VERSION" \
  --namespace "$CM_NS" --create-namespace \
  --set crds.enabled=true --set global.leaderElection.namespace="$CM_NS" --wait --timeout 5m >/dev/null
kubectl -n "$LAB_NS" apply -f - >/dev/null <<'YAML'
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: site
spec:
  secretName: site-tls
  dnsNames:
    - site.example.test
  issuerRef:
    kind: Issuer
    name: selfsigned
YAML
kubectl -n "$LAB_NS" wait --for=condition=Ready certificate.cert-manager.io/site --timeout=180s >/dev/null
