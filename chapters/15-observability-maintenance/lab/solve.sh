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

# Task 1: the previous run's logs if the kubelet still has them, else the current run's.
# `logs --previous` can exit 0 with an error message instead of logs, so check the output.
out="$(k logs crasher --previous 2>/dev/null || true)"
if ! grep -q 'fatal' <<<"$out"; then
  out="$(k logs crasher)"
fi
grep -m1 'fatal' <<<"$out" > "$LAB_ANSWER_FILE"

# Task 2: the environment cannot change in place; replace the Pod
k delete pod crasher --wait=true >/dev/null
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: crasher
spec:
  containers:
    - name: crasher
      image: busybox:1.36
      env:
        - name: DATABASE_URL
          value: postgres://db:5432/shop
      command:
        - sh
        - -c
        - |
          if [ -z "$DATABASE_URL" ]; then
            echo "fatal: missing config DATABASE_URL"
            exit 3
          fi
          echo "connected"
          sleep 3600
YAML
k wait --for=condition=Ready pod/crasher --timeout=180s >/dev/null

# Task 3
k logs -l app=checkout --tail=3 > "$LAB_LOG_FILE"

# Task 4
k patch deployment checkout -p '{"spec":{"template":{"metadata":{"annotations":{"observability.example.com/scrape":"true"}}}}}' >/dev/null
k rollout status deployment/checkout --timeout=180s >/dev/null

# Task 5
k apply -f - >/dev/null <<'YAML'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: checkout-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: checkout
YAML
