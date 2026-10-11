#!/usr/bin/env bash
# Automated reference solution (used by CI). Human-readable version: solutions.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

chart="${here}/.state/charts/shop"

# Task 1
helm -n "$LAB_NS" install shop "$chart" --set replicaCount=2 >/dev/null

# Task 2
helm -n "$LAB_NS" upgrade shop "$chart" --reuse-values --set image.tag=1.27 >/dev/null

# Task 3
helm -n "$LAB_NS" rollback shop 1 >/dev/null

# Task 4
kubectl -n "$LAB_NS" apply -k "${here}/.state/kustomize/overlay" >/dev/null

# Task 5
helm -n "$LAB_NS" install greeter "$chart" --set greeting=hello >/dev/null

kubectl -n "$LAB_NS" rollout status deployment/shop --timeout=180s >/dev/null
kubectl -n "$LAB_NS" rollout status deployment/api --timeout=180s >/dev/null
kubectl -n "$LAB_NS" rollout status deployment/greeter --timeout=180s >/dev/null
