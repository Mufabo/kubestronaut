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
pw="$(cat "${here}/.state/db-password")"

# Task 1
k create configmap app-config --from-literal=LOG_LEVEL=info --from-literal=FEATURE_FLAG=on >/dev/null

# Task 2
k create secret generic db-credentials --from-literal=username=app --from-literal=password="$pw" >/dev/null

# Task 3
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: web
spec:
  containers:
    - name: web
      image: nginx:1.27
      envFrom:
        - configMapRef:
            name: app-config
      env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
YAML

# Task 4
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: reporter
spec:
  containers:
    - name: reporter
      image: busybox:1.36
      command: ["sleep", "3600"]
      resources:
        limits:
          memory: 64Mi
      env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: MEM_LIMIT
          valueFrom:
            resourceFieldRef:
              containerName: reporter
              resource: limits.memory
              divisor: 1Mi
YAML

# Task 5
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: config-viewer
spec:
  containers:
    - name: viewer
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: config
          mountPath: /etc/app
        - name: creds
          mountPath: /etc/db
          readOnly: true
  volumes:
    - name: config
      configMap:
        name: app-config
    - name: creds
      secret:
        secretName: db-credentials
YAML

info "Waiting for the Pods to run"
for p in web reporter config-viewer; do
  wait_for "pod ${p} Running" 180 pod_phase_is "$LAB_NS" "$p" Running
done
