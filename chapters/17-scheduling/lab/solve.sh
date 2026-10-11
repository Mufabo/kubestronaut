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

k() { kubectl -n "$LAB_NS" "$@"; }

# Task 1
k apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: pinned
spec:
  nodeSelector:
    disk: ssd
  containers:
    - name: pinned
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML

# Task 2
k apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: tolerant
spec:
  nodeSelector:
    kubernetes.io/hostname: ${WORKER_B}
  tolerations:
    - key: maintenance
      operator: Equal
      value: "true"
      effect: NoSchedule
  containers:
    - name: tolerant
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML

# Task 3
k apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cache
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cache
  template:
    metadata:
      labels:
        app: cache
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - topologyKey: kubernetes.io/hostname
              labelSelector:
                matchLabels:
                  app: cache
      containers:
        - name: cache
          image: busybox:1.36
          command: ["sleep", "3600"]
YAML

# Task 4
kubectl apply -f - >/dev/null <<YAML
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: ${LAB_PRIORITYCLASS}
value: 100000
description: Batch work that may run ahead of ordinary Pods
YAML
k apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: urgent
spec:
  priorityClassName: ${LAB_PRIORITYCLASS}
  containers:
    - name: urgent
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML

# Task 5: the static Pods are the ones with a Node owner
kubectl -n kube-system get pods -o jsonpath='{range .items[?(@.metadata.ownerReferences[0].kind=="Node")]}{.metadata.name}{"\n"}{end}' | grep kube-scheduler > "$LAB_ANSWER_FILE"

for p in pinned tolerant; do k wait --for=condition=Ready "pod/${p}" --timeout=180s >/dev/null; done
k wait --for=jsonpath='{.status.phase}'=Running pod/urgent --timeout=180s >/dev/null
k rollout status deployment/cache --timeout=180s >/dev/null
