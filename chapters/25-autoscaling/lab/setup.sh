#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
rm -f "$LAB_ANSWER_METRIC" "$LAB_ANSWER_HPA_API"
lab_create_ns "$LAB_NS"

# A Deployment that burns CPU, with a request, so its utilization is measurable.
# The HPA in Task 1 scales it; the limit caps each Pod at half a core.
kubectl -n "$LAB_NS" apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: api
          image: busybox:1.36
          command: ["sh", "-c", "while true; do :; done"]
          resources:
            requests:
              cpu: 100m
            limits:
              cpu: 500m
YAML
kubectl -n "$LAB_NS" rollout status deployment/api --timeout=180s >/dev/null

info "Lab ready. Namespace: ${LAB_NS}. Deployment api has 1 replica and a CPU request of 100m"
