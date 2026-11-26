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

# Tasks 1 and 4: the HPA, with a scale-down window
k apply -f - >/dev/null <<'YAML'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 1
  maxReplicas: 4
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 60
YAML

# Task 2: wait for the scale-up
for _ in $(seq 1 60); do
  ready="$(k get deployment api -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
  [[ "${ready:-0}" -ge 2 ]] && break
  sleep 5
done

# Task 3
k get hpa api -o jsonpath='{.status.currentMetrics[0].resource.name}' > "$LAB_ANSWER_METRIC"

# Task 5
kubectl api-resources --api-group=autoscaling --no-headers | awk '$NF=="HorizontalPodAutoscaler"{print $3}' > "$LAB_ANSWER_HPA_API"

# Task 6: a VPA that only recommends, then wait for the recommendation
k apply -f - >/dev/null <<'YAML'
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: worker
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: worker
  updatePolicy:
    updateMode: "Off"
YAML
has_recommendation() {
  [[ -n "$(k get vpa worker -o jsonpath='{.status.recommendation.containerRecommendations[0].target.cpu}' 2>/dev/null)" ]]
}
wait_for "the VPA recommendation for worker" 300 has_recommendation

# Task 7: wait until every batch Pod has metrics, then take the first line
batch_metrics() {
  [[ "$(kubectl top pods -n "$LAB_NS" -l tier=batch --no-headers 2>/dev/null | wc -l)" -eq 3 ]]
}
wait_for "metrics for the batch Pods" 180 batch_metrics
kubectl top pods -n "$LAB_NS" -l tier=batch --sort-by=cpu --no-headers | awk 'NR==1{print $1}' > "$LAB_ANSWER_TOP_POD"
