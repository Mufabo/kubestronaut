#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
rm -f "$LAB_ANSWER_METRIC" "$LAB_ANSWER_HPA_API" "$LAB_ANSWER_TOP_POD"
install_vpa
lab_create_ns "$LAB_NS"

# Task 6: a steady worker for the VPA to measure. No HPA scales it, so the
# two autoscalers never act on the same workload.
kubectl -n "$LAB_NS" apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: worker
  template:
    metadata:
      labels:
        app: worker
    spec:
      containers:
        - name: worker
          image: busybox:1.36
          command: ["sh", "-c", "while true; do :; done"]
          resources:
            requests:
              cpu: 50m
              memory: 16Mi
            limits:
              cpu: 200m
              memory: 64Mi
YAML

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
kubectl -n "$LAB_NS" rollout status deployment/worker --timeout=180s >/dev/null

# Task 7: three batch Pods with different, steady CPU use. batch-2 is the busiest:
# its request equals its limit, so it keeps its lead even on a busy node.
batch_pod() {  # <name> <command> <cpu>
  kubectl -n "$LAB_NS" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $1
  labels:
    tier: batch
spec:
  containers:
    - name: job
      image: busybox:1.36
      command: ["sh", "-c", "$2"]
      resources:
        requests:
          cpu: $3
        limits:
          cpu: $3
YAML
}
batch_pod batch-1 "sleep 3600" 20m
batch_pod batch-2 "while true; do :; done" 200m
batch_pod batch-3 "while true; do :; done" 50m
kubectl -n "$LAB_NS" wait --for=condition=Ready pod -l tier=batch --timeout=180s >/dev/null

info "Lab ready. Namespace: ${LAB_NS}. Deployment api has 1 replica and a CPU request of 100m; Deployment worker is for Task 6; the VPA recommender runs in kube-system; Pods batch-1 to batch-3 are for Task 7"
