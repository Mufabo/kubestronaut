#!/usr/bin/env bash
# Chapter 49 lab: a brand-new kind cluster with no CNI plugin. Two Pods wait
# for a network: client (netshoot, on kbook-worker) and web (agnhost, on
# kbook-worker2). The reader installs Cilium with Helm and tunes it.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_cmd helm

cluster_fresh "$LAB_PROFILE"
lab_course_reset "$LAB_ANSWERS" .
lab_create_ns "$LAB_NS"

kubectl -n "$LAB_NS" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: client
  labels: {app: client}
spec:
  nodeSelector: {kubernetes.io/hostname: kbook-worker}
  terminationGracePeriodSeconds: 0
  containers:
    - name: client
      image: ${NETSHOOT_IMAGE}
      command: ["sleep", "infinity"]
---
apiVersion: v1
kind: Pod
metadata:
  name: web
  labels: {app: web}
spec:
  nodeSelector: {kubernetes.io/hostname: kbook-worker2}
  terminationGracePeriodSeconds: 0
  containers:
    - name: web
      image: ${AGNHOST_IMAGE}
      args: ["netexec", "--http-port=8080"]
      ports: [{containerPort: 8080}]
YAML
info "Lab ready: the nodes have no network plugin yet. Install Cilium ${CILIUM_VERSION} (chart cilium from https://helm.cilium.io)."
