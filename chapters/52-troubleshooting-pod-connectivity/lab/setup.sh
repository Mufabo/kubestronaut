#!/usr/bin/env bash
# Chapter 52 lab: a brand-new cilium cluster with three faults to find.
#   - client (kbook-worker) uses the node's resolver instead of cluster DNS
#   - the Deployment api listens on 127.0.0.1 only
#   - kbook-worker2 drops Cilium's VXLAN traffic (UDP 8472) in its INPUT chain
# web (kbook-worker2, behind the Service web) is healthy. CoreDNS is kept on
# the control plane, so DNS does not depend on the blocked node.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

cluster_fresh "$LAB_PROFILE"
kubectl -n kube-system patch deployment coredns --type=merge \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"node-role.kubernetes.io/control-plane":""}}}}}' >/dev/null
kubectl -n kube-system rollout status deployment/coredns --timeout=300s >/dev/null
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
  dnsPolicy: Default
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
---
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector: {app: web}
  ports: [{port: 8080, targetPort: 8080}]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 1
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      nodeSelector: {kubernetes.io/hostname: kbook-worker}
      terminationGracePeriodSeconds: 0
      containers:
        - name: api
          image: ${NETSHOOT_IMAGE}
          command: ["socat", "TCP-LISTEN:8080,bind=127.0.0.1,fork,reuseaddr", "SYSTEM:echo api-ok"]
YAML
kubectl -n "$LAB_NS" wait --for=condition=Ready pod/client pod/web --timeout=300s >/dev/null
kubectl -n "$LAB_NS" rollout status deployment/api --timeout=300s >/dev/null

# The node-level fault: a firewall rule that drops the overlay on kbook-worker2.
node_exec kbook-worker2 iptables -I INPUT -p udp --dport 8472 -j DROP
info "Lab ready. Something is wrong with client, api, and kbook-worker2."
