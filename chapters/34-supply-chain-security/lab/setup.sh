#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_cmd docker trivy cosign
require_lab_cluster
lab_teardown_ns "$LAB_NS"
lab_teardown_ns "$LAB_SCAN_NS"
# Cluster-scoped leftovers from a previous run, and the files and registry of Tasks 3 to 6.
kubectl delete validatingadmissionpolicybinding "$LAB_BINDING" --ignore-not-found >/dev/null
kubectl delete validatingadmissionpolicy "$LAB_POLICY" --ignore-not-found >/dev/null
rm -f "$LAB_DIGEST_FILE" "$LAB_CRITICAL_FILE" "$LAB_COSIGN_KEY" "$LAB_COSIGN_PUB"
docker rm -f "$LAB_REGISTRY_CONTAINER" >/dev/null 2>&1 || true
lab_create_ns "$LAB_NS"
lab_create_ns "$LAB_SCAN_NS"
# Deleting a policy takes effect in admission a moment later, so wait until a Pod is no longer refused.
wait_for "the previous image policy to stop applying" 60 \
  kubectl -n "$LAB_NS" run policy-probe --image=nginx:1.27 --restart=Never --dry-run=server -- true

# A Pod that already runs before any policy exists. Task 3 reads its image digest.
kubectl -n "$LAB_NS" run runner --image=busybox:1.36 --restart=Never -- sleep 3600 >/dev/null

# Task 4: a Deployment that static analysis has much to say about.
kubectl -n "$LAB_SCAN_NS" apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: report
spec:
  replicas: 2
  selector:
    matchLabels:
      app: report
  template:
    metadata:
      labels:
        app: report
    spec:
      hostNetwork: true
      containers:
        - name: report
          image: busybox:1.36
          command: ["sleep", "infinity"]
          securityContext:
            privileged: true
          resources:
            requests: {cpu: 10m, memory: 16Mi}
            limits: {cpu: 100m, memory: 32Mi}
YAML

# Task 5: four Pods whose images the reader scans; verify reads the list back.
mkdir -p "${here}/.state"
: > "${here}/.state/scan-images"
for spec in legacy-web=nginx:1.19 legacy-proxy=httpd:2.4.46 tools=alpine:3.20 holder=registry.k8s.io/pause:3.10; do
  name="${spec%%=*}"; image="${spec#*=}"
  command=""
  [[ "$name" == tools ]] && command='      command: ["sleep", "infinity"]'
  printf '%s %s\n' "$name" "$image" >> "${here}/.state/scan-images"
  kubectl -n "$LAB_SCAN_NS" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
  labels:
    scan: me
spec:
  containers:
    - name: ${name}
      image: ${image}
${command}
      resources:
        requests: {cpu: 10m, memory: 16Mi}
        limits: {memory: 64Mi}
YAML
done
# The vulnerability database, so that scans can run offline (trivy --skip-db-update).
info "Downloading Trivy's vulnerability database"
trivy image --download-db-only --quiet

# Task 6: a local registry with two images: app:1.0 to sign, app:1.1 to leave unsigned.
docker run -d --name "$LAB_REGISTRY_CONTAINER" -p "127.0.0.1:${LAB_REGISTRY##*:}:5000" "$LAB_REGISTRY_IMAGE" >/dev/null
registry_up() { curl -fsS "http://${LAB_REGISTRY}/v2/" >/dev/null; }
wait_for "the local registry" 60 registry_up
for v in 1.0 1.1; do
  printf 'FROM busybox:1.36\nLABEL version=%s\nCMD ["sleep", "infinity"]\n' "$v" |
    docker build -q -t "${LAB_REGISTRY}/ch34/app:${v}" - >/dev/null
  docker push -q "${LAB_REGISTRY}/ch34/app:${v}" >/dev/null
done

kubectl -n "$LAB_NS" wait --for=condition=Ready pod/runner --timeout=180s >/dev/null
kubectl -n "$LAB_SCAN_NS" rollout status deployment/report --timeout=180s >/dev/null
kubectl -n "$LAB_SCAN_NS" wait --for=condition=Ready pod -l scan=me --timeout=300s >/dev/null
info "Lab ready. Namespaces: ${LAB_NS} (runner, no image policy yet) and ${LAB_SCAN_NS}; registry ${LAB_REGISTRY}"
