#!/usr/bin/env bash
# Chapter 53 lab: two small apps without working Services.
#   shop: 3 replicas of a test server on port 8080 (no Service yet)
#   cart: 2 replicas on port 9090, behind a Service with a wrong targetPort
#   client: a netshoot Pod to test from; ch53-outside: a netshoot container on
#   the kind Docker network, outside the cluster.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

cluster_require "$LAB_PROFILE"
docker rm -f ch53-outside >/dev/null 2>&1 || true
kubectl delete ciliumloadbalancerippools.cilium.io ch53-pool --ignore-not-found >/dev/null
lab_teardown_ns "$LAB_NS"
lab_create_ns "$LAB_NS"
lab_course_reset "$LAB_ANSWERS" .

kubectl -n "$LAB_NS" apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop
spec:
  replicas: 3
  selector:
    matchLabels: {app: shop}
  template:
    metadata:
      labels: {app: shop, tier: web}
    spec:
      terminationGracePeriodSeconds: 0
      containers:
        - name: shop
          image: ${AGNHOST_IMAGE}
          args: ["netexec", "--http-port=8080"]
          ports: [{name: http, containerPort: 8080}]
          readinessProbe:
            httpGet: {path: /, port: 8080}
            periodSeconds: 2
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cart
spec:
  replicas: 2
  selector:
    matchLabels: {app: cart}
  template:
    metadata:
      labels: {app: cart, tier: api}
    spec:
      terminationGracePeriodSeconds: 0
      containers:
        - name: cart
          image: ${AGNHOST_IMAGE}
          args: ["netexec", "--http-port=9090"]
          ports: [{name: api, containerPort: 9090}]
          readinessProbe:
            httpGet: {path: /, port: 9090}
            periodSeconds: 2
---
apiVersion: v1
kind: Service
metadata:
  name: cart
spec:
  selector: {app: cart}
  ports:
    - name: http
      port: 80
      targetPort: 8080
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  labels: {app: client}
spec:
  terminationGracePeriodSeconds: 0
  containers:
    - name: client
      image: ${NETSHOOT_IMAGE}
      command: ["sleep", "infinity"]
YAML

docker run -d --name ch53-outside --label kubestronaut.io/lab=outside --network kind \
  "$NETSHOOT_IMAGE" sleep infinity >/dev/null
kubectl -n "$LAB_NS" rollout status deployment/shop --timeout=180s >/dev/null
kubectl -n "$LAB_NS" rollout status deployment/cart --timeout=180s >/dev/null
kubectl -n "$LAB_NS" wait --for=condition=Ready pod/client --timeout=180s >/dev/null
info "Lab ready. Test from inside with: kubectl -n ${LAB_NS} exec client -- curl ..."
info "Test from outside the cluster with: docker exec ch53-outside curl ..."
