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
kubectl get node "${CLUSTER_NAME}-worker" -o jsonpath='{.spec.podCIDR}' > "$LAB_ANSWER_CIDR"

# Task 2
k get service backend -o jsonpath='{.spec.clusterIP}' > "$LAB_ANSWER_IP"

# Task 3
k apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes:
    - Ingress
YAML

# Task 4
k apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: client
      ports:
        - protocol: TCP
          port: 80
YAML

# Task 5
kubectl -n kube-system get configmap kube-proxy -o jsonpath='{.data.config\.conf}' | sed -n 's/^mode: *"\{0,1\}\([a-z]*\)"\{0,1\}$/\1/p' | head -1 > "$LAB_ANSWER_PROXY"
