#!/usr/bin/env bash
# Automated reference solution (used by CI). Human-readable version: solutions.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_lab_cluster

# Task 1
kubectl get pods -A --field-selector metadata.name=lost-cat -o jsonpath='{.items[0].metadata.namespace}' > "$LAB_ANSWER_NS"

# Task 2
kubectl create namespace ch06-payments >/dev/null
kubectl label namespace ch06-payments team=payments >/dev/null
kubectl -n ch06-payments run ledger --image=nginx:1.27 --labels=app=ledger >/dev/null

# Task 4 (before Task 3, whose replacement Pod is briefly Pending)
kubectl -n "$LAB_NS" get pods --field-selector status.phase!=Running -o name > "$LAB_ANSWER_PODS"

# Task 3
degraded="$(kubectl -n "$LAB_NS" get pods -o jsonpath='{.items[?(@.metadata.annotations.status=="degraded")].metadata.name}')"
kubectl -n "$LAB_NS" label pod "$degraded" app=queue-debug --overwrite >/dev/null

# Task 5: a node the Pod can actually use (the control plane is tainted in a
# multi-node cluster)
node="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.spec.taints[*].effect}{"\n"}{end}' |
  awk '$0 !~ /NoSchedule/ {print $1; exit}')"
kubectl label node "$node" "${LAB_NODE_LABEL}=ssd" >/dev/null

info "Waiting for the Pods to settle"
wait_for "ledger Running" 180 pod_phase_is ch06-payments ledger Running
wait_for "fast-io Running" 180 pod_phase_is ch06-blue fast-io Running
queue_ready() { [[ "$(kubectl -n "$LAB_NS" get deployment queue -o jsonpath='{.status.readyReplicas}')" == "3" ]]; }
wait_for "queue back to 3 ready Pods" 120 queue_ready
