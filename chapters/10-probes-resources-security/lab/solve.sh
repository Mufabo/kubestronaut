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
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: gate
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      readinessProbe:
        exec:
          command: ["cat", "/tmp/ready"]
        periodSeconds: 2
YAML
k wait --for=jsonpath='{.status.phase}'=Running pod/gate --timeout=120s >/dev/null
k exec gate -- touch /tmp/ready

# Task 2
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: healthy
spec:
  containers:
    - name: app
      image: nginx:1.27
      livenessProbe:
        httpGet:
          path: /
          port: 80
        initialDelaySeconds: 5
        periodSeconds: 10
YAML

# Task 3
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: sized
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      resources:
        requests:
          cpu: 100m
          memory: 64Mi
        limits:
          cpu: 200m
          memory: 128Mi
YAML

# Task 4
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: pinned
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      resources:
        requests:
          cpu: 250m
          memory: 128Mi
        limits:
          cpu: 250m
          memory: 128Mi
YAML

# Task 5
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: hardened
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
YAML

info "Waiting for the Pods to be ready"
for p in gate healthy sized pinned hardened; do
  k wait --for=condition=Ready "pod/${p}" --timeout=180s >/dev/null
done
