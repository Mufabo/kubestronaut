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
  name: pair
spec:
  volumes:
    - name: shared
      emptyDir: {}
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh", "-c", "while true; do date >> /shared/out.txt; sleep 1; done"]
      volumeMounts:
        - name: shared
          mountPath: /shared
    - name: reader
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3; tail -f /shared/out.txt"]
      volumeMounts:
        - name: shared
          mountPath: /shared
YAML

# Task 2
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: setup
spec:
  volumes:
    - name: work
      emptyDir: {}
  initContainers:
    - name: prepare
      image: busybox:1.36
      command: ["sh", "-c", "echo ready > /work/status.txt"]
      volumeMounts:
        - name: work
          mountPath: /work
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: work
          mountPath: /work
YAML

# Task 3: the init command cannot change in place, so replace the Pod
k delete pod checked --wait=true >/dev/null
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: checked
spec:
  initContainers:
    - name: check
      image: busybox:1.36
      command: ["sh", "-c", "echo checking the config; exit 0"]
  containers:
    - name: main
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML

# Task 4
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: logged
spec:
  volumes:
    - name: logs
      emptyDir: {}
  initContainers:
    - name: shipper
      image: busybox:1.36
      restartPolicy: Always
      command: ["sh", "-c", "touch /var/log/app/app.log; tail -F /var/log/app/app.log"]
      volumeMounts:
        - name: logs
          mountPath: /var/log/app
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "while true; do echo request handled; sleep 2; done >> /var/log/app/app.log"]
      volumeMounts:
        - name: logs
          mountPath: /var/log/app
YAML

# Task 5
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: debug
spec:
  shareProcessNamespace: true
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
    - name: helper
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML

# Task 6
k apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
spec:
  selector:
    matchLabels:
      app: node-agent
  template:
    metadata:
      labels:
        app: node-agent
    spec:
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      containers:
        - name: agent
          image: busybox:1.36
          command: ["sh", "-c", "echo \"agent on $NODE_NAME\"; sleep 3600"]
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
YAML
k rollout status daemonset/node-agent --timeout=300s >/dev/null

info "Waiting for the Pods to run"
k wait --for=condition=Ready pod/pair --timeout=180s >/dev/null
for p in setup checked logged debug; do
  wait_for "pod ${p} Ready" 180 pod_phase_is "$LAB_NS" "$p" Running
done
