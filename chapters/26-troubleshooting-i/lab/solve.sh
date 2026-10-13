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

# Fault 1
k set image deployment/api api=nginx:1.27 >/dev/null
k rollout status deployment/api --timeout=180s >/dev/null

# Fault 2
k patch service web -p '{"spec":{"selector":{"app":"web"}}}' >/dev/null

# Fault 3
k patch service app -p '{"spec":{"ports":[{"port":80,"targetPort":8080}]}}' >/dev/null

# Fault 4: admit the client's role on port 8080
k apply -f - >/dev/null <<'YAML'
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
              role: client
      ports:
        - protocol: TCP
          port: 8080
YAML

# Fault 5: a dnsConfig cannot change in place, so the Pod is replaced with the cluster DNS address
dns_ip="$(kubectl -n kube-system get service kube-dns -o jsonpath='{.spec.clusterIP}')"
k delete pod resolver --wait=true >/dev/null
k apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: resolver
spec:
  dnsPolicy: None
  dnsConfig:
    nameservers: ["${dns_ip}"]
    searches: ["${LAB_NS}.svc.cluster.local", "svc.cluster.local", "cluster.local"]
    options:
      - name: ndots
        value: "5"
  containers:
    - name: resolver
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML
k wait --for=condition=Ready pod/resolver --timeout=180s >/dev/null
