#!/usr/bin/env bash
# Chapter 48 lab: a kind cluster with no CNI plugin. The nodes are NotReady,
# and two Pods wait to be scheduled: client (on kbook-worker) and web (on
# kbook-worker2, behind the Service web). A server outside the cluster,
# ch48-outside, runs as a plain Docker container on the kind network.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

docker rm -f ch48-outside >/dev/null 2>&1 || true
cluster_fresh "$LAB_PROFILE"
# CoreDNS would land on any node; keep it on the control plane, so Task 4
# always needs routes to the control plane's Pod CIDR as well.
kubectl -n kube-system patch deployment coredns --type=merge \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"node-role.kubernetes.io/control-plane":""}}}}}' >/dev/null
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
---
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector: {app: web}
  ports: [{port: 8080, targetPort: 8080}]
YAML

# The outside world: a web server on the kind Docker network, not in the cluster.
docker run -d --name ch48-outside --label kubestronaut.io/lab=outside --network kind \
  "$AGNHOST_IMAGE" netexec --http-port=8080 >/dev/null
mkdir -p "${here}/.state"
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ch48-outside > "${here}/.state/outside-ip"
info "Lab ready. The outside server is http://$(cat "${here}/.state/outside-ip"):8080"
