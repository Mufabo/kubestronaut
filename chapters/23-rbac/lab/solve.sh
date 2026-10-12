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
k create serviceaccount reporter >/dev/null
k create role pod-reader --verb=get,list --resource=pods >/dev/null
k create rolebinding reporter-reads-pods --role=pod-reader --serviceaccount="${LAB_NS}:reporter" >/dev/null

# Task 2
kubectl create clusterrole "$LAB_CLUSTERROLE" --verb=get,list --resource=nodes >/dev/null
kubectl create clusterrolebinding "$LAB_CLUSTERROLEBINDING" --clusterrole="$LAB_CLUSTERROLE" --serviceaccount="${LAB_NS}:reporter" >/dev/null

# Task 3
k apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: probe
spec:
  serviceAccountName: reporter
  containers:
    - name: probe
      image: curlimages/curl:8.11.1
      command: ["sleep", "3600"]
YAML
k wait --for=condition=Ready pod/probe --timeout=180s >/dev/null

# Task 4
k patch serviceaccount builder -p '{"automountServiceAccountToken":false}' >/dev/null
k apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: quiet
spec:
  serviceAccountName: builder
  containers:
    - name: quiet
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML
k wait --for=condition=Ready pod/quiet --timeout=180s >/dev/null

# Task 5
kubectl auth can-i delete pods --as="system:serviceaccount:${LAB_NS}:reporter" -n "$LAB_NS" > "$LAB_ANSWER_CAN_DELETE" || true
