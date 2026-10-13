#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
lab_create_ns "$LAB_NS"

# Five independent faults, one per task. Each is broken on purpose, in a way the
# reader finds with the commands of this chapter.
kubectl -n "$LAB_NS" apply -f - >/dev/null <<'YAML'
# Fault 1: the image tag does not exist, so the Pod cannot be pulled.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: api
          image: nginx:1.27-typo
---
# A healthy HTTP app on port 8080.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 1
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
          image: busybox:1.36
          command: ["sh", "-c", "mkdir -p /www && echo app-ok > /www/index.html && httpd -f -p 8080 -h /www"]
          ports:
            - containerPort: 8080
---
# Fault 3: the Service sends traffic to port 80, where nothing listens.
apiVersion: v1
kind: Service
metadata:
  name: app
spec:
  selector:
    app: app
  ports:
    - port: 80
      targetPort: 80
---
# A healthy web Deployment, and a Service whose selector has a typo (Fault 2).
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx:1.27
---
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector:
    app: wbe
  ports:
    - port: 80
      targetPort: 80
---
# Fault 4: a policy that admits only role=other on port 8080, so the client is cut off.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: lock
spec:
  podSelector:
    matchLabels:
      app: app
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: other
      ports:
        - protocol: TCP
          port: 8080
---
# The client that tests the services and the policy.
apiVersion: v1
kind: Pod
metadata:
  name: client
  labels:
    role: client
spec:
  containers:
    - name: client
      image: curlimages/curl:8.11.1
      command: ["sleep", "3600"]
---
# Fault 5: this Pod resolves names through a nameserver that does not answer.
apiVersion: v1
kind: Pod
metadata:
  name: resolver
spec:
  dnsPolicy: None
  dnsConfig:
    nameservers: ["10.0.0.1"]
    searches: ["ch26-broken.svc.cluster.local", "svc.cluster.local", "cluster.local"]
    options:
      - name: ndots
        value: "5"
  containers:
    - name: resolver
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML

kubectl -n "$LAB_NS" wait --for=condition=Ready pod/client pod/resolver --timeout=180s >/dev/null
kubectl -n "$LAB_NS" rollout status deployment/app --timeout=180s >/dev/null
kubectl -n "$LAB_NS" rollout status deployment/web --timeout=180s >/dev/null

info "Lab ready. Namespace: ${LAB_NS}. Five faults are in place; find and fix each one"
