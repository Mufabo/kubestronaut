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
docker build -q -t "$LAB_IMAGE" "${here}/.state/app" >/dev/null
kind load docker-image "$LAB_IMAGE" --name "$CLUSTER_NAME" >/dev/null

# Task 2
k apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
    spec:
      containers:
        - name: app
          image: ${LAB_IMAGE}
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 80
YAML
k rollout status deployment/app --timeout=180s >/dev/null

# Task 3
k patch deployment legacy --type=merge -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}' >/dev/null
k rollout status deployment/legacy --timeout=180s >/dev/null

# Task 4
k patch deployment app --type=merge -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxUnavailable":0,"maxSurge":1}}}}' >/dev/null
k rollout status deployment/app --timeout=180s >/dev/null

# Task 5
k create secret docker-registry regcred --docker-server=registry.example.test \
  --docker-username=ci --docker-password=not-a-real-token >/dev/null
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: private-app
spec:
  imagePullSecrets:
    - name: regcred
  containers:
    - name: app
      image: registry.example.test/team/app:1.0
YAML
