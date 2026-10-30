#!/usr/bin/env bash
# Automated reference solution (used by the test loop on cp1). Human-readable
# version: solutions.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_snapshot "$LAB_SNAPSHOT"
require_lab_cluster

# Task 1: the dry run's warnings name the violating Pods.
warnings="$(kubectl label --dry-run=server --overwrite namespace ch33-legacy pod-security.kubernetes.io/enforce=baseline 2>&1 >/dev/null)"
sed -n 's/^Warning: \([a-z0-9-]*\): .*/\1/p' <<<"$warnings" | sort > "$VIOLATIONS_FILE"
kubectl label --overwrite namespace ch33-legacy pod-security.kubernetes.io/enforce=baseline pod-security.kubernetes.io/warn=restricted >/dev/null 2>&1

# Task 2
kubectl -n ch33-apps patch deployment worker -p '{"spec":{"template":{"spec":{
  "securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},
  "containers":[{"name":"busybox","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}}}' >/dev/null

# Task 3
kubectl -n ch33-apps apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: api
spec:
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  volumes:
    - name: db
      secret:
        secretName: db-pass
        defaultMode: 0400
  containers:
    - name: api
      image: busybox:1.36
      command: ["sleep", "infinity"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
      volumeMounts:
        - name: db
          mountPath: /etc/db
          readOnly: true
YAML

# Task 4: the configuration, the API server's flag, volume, and mount, then a rewrite.
key="$(head -c 32 /dev/urandom | base64)"
sudo mkdir -p "$(dirname "$ENC_CONFIG")"
sudo tee "$ENC_CONFIG" >/dev/null <<YAML
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${key}
      - identity: {}
YAML
sudo chmod 600 "$ENC_CONFIG"
sudo sed -i \
  -e "s|^    - kube-apiserver\$|    - kube-apiserver\n    - --encryption-provider-config=${ENC_CONFIG}|" \
  -e 's|^    volumeMounts:$|    volumeMounts:\n    - mountPath: /etc/kubernetes/enc\n      name: enc\n      readOnly: true|' \
  -e 's|^  volumes:$|  volumes:\n  - hostPath:\n      path: /etc/kubernetes/enc\n      type: DirectoryOrCreate\n    name: enc|' \
  "$APISERVER_MANIFEST"
encrypting_apiserver_up() {
  local pid
  pid="$(pgrep -f 'kube-apiserver --' | head -1)"
  [[ -n "$pid" ]] && sudo grep -q -- '--encryption-provider-config' "/proc/${pid}/cmdline" 2>/dev/null &&
    kubectl get --raw /readyz >/dev/null 2>&1
}
wait_for "the API server to come back with encryption at rest" 300 encrypting_apiserver_up
secrets="$(kubectl -n ch33-apps get secrets -o json)"
kubectl replace -f - <<<"$secrets" >/dev/null

# Task 5
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
---
apiVersion: v1
kind: Pod
metadata:
  name: sandboxed
  namespace: ch33-sandbox
spec:
  runtimeClassName: gvisor
  containers:
    - name: sandboxed
      image: busybox:1.36
      command: ["sleep", "infinity"]
YAML

kubectl -n ch33-apps rollout status deployment/worker --timeout=180s >/dev/null
kubectl -n ch33-apps wait --for=condition=Ready pod/api --timeout=180s >/dev/null
kubectl -n ch33-sandbox wait --for=condition=Ready pod/sandboxed --timeout=180s >/dev/null
