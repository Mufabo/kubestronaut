#!/usr/bin/env bash
# Tier 2: the starting state is the cluster snapshot, Falco on node1, and the
# Namespace ch35-apps with three suspects, a canary, an nginx Deployment that can
# write its own files, and a Pod to quarantine.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

require_snapshot "$LAB_SNAPSHOT"
[[ "$(hostname)" == cp1 ]] || die "run this lab on cp1 (envs/vagrant/kbook-vm ssh)"
require_lab_cluster
if apiserver_audits; then
  die "the API server already writes an audit log (Task 1). To start over, restore the snapshot on the host: envs/vagrant/kbook-vm restore ${LAB_SNAPSHOT}"
fi
on node1 true || die "cannot ssh to node1 from cp1"

# Falco (Tasks 2 and 3), without a custom rule from an earlier run.
install_falco
# shellcheck disable=SC2029
if on node1 "test -e ${FALCO_RULES}"; then
  on node1 "sudo rm -f ${FALCO_RULES} && sudo systemctl restart ${FALCO_UNIT}"
fi
on node1 "sudo systemctl enable --now ${FALCO_UNIT} >/dev/null 2>&1"
wait_for "Falco running on node1" 60 falco_running

# A clean start: the Namespace and the answer file.
lab_teardown_ns "$LAB_NS"
rm -f "$FALCO_FILE"
mkdir -p "$STATE"
lab_create_ns "$LAB_NS"

# Task 2: three look-alike Deployments on node1; one of them reads /etc/shadow.
bad="${SUSPECTS[RANDOM % ${#SUSPECTS[@]}]}"
printf '%s\n' "$bad" > "${STATE}/suspect"
for name in "${SUSPECTS[@]}"; do
  case "$name" in
    "$bad")    script='while true; do cat /etc/shadow >/dev/null; sleep 20; done' ;;
    inventory) script='while true; do cat /etc/hostname >/dev/null; sleep 20; done' ;;
    *)         script='while true; do ls /tmp >/dev/null; sleep 20; done' ;;
  esac
  payload="$(printf '%s' "$script" | base64 -w0)"
  kubectl -n "$LAB_NS" apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${name}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${name}
  template:
    metadata:
      labels:
        app: ${name}
    spec:
      nodeSelector:
        kubernetes.io/hostname: node1
      containers:
        - name: worker
          image: busybox:1.36
          command: ["sh", "-c", "echo ${payload} | base64 -d | sh"]
          resources:
            requests: {cpu: 10m, memory: 16Mi}
            limits: {memory: 32Mi}
YAML
done

# Tasks 3, 4, and 5: the canary on node1, the web server, and the Pod to isolate.
kubectl -n "$LAB_NS" apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: canary
spec:
  nodeSelector:
    kubernetes.io/hostname: node1
  containers:
    - name: canary
      image: busybox:1.36
      command: ["sleep", "infinity"]
      resources:
        requests: {cpu: 10m, memory: 16Mi}
        limits: {memory: 32Mi}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          resources:
            requests: {cpu: 10m, memory: 32Mi}
            limits: {memory: 64Mi}
---
apiVersion: v1
kind: Pod
metadata:
  name: miner
  labels:
    app: miner
spec:
  containers:
    - name: miner
      image: busybox:1.36
      command: ["sh", "-c", "while true; do wget -q -T 2 -O /dev/null http://web 2>/dev/null; sleep 10; done"]
      resources:
        requests: {cpu: 10m, memory: 16Mi}
        limits: {memory: 32Mi}
YAML
kubectl -n "$LAB_NS" expose deployment web --port=80 >/dev/null

for d in "${SUSPECTS[@]}" web; do
  kubectl -n "$LAB_NS" rollout status "deployment/${d}" --timeout=180s >/dev/null
done
kubectl -n "$LAB_NS" wait --for=condition=Ready pod/canary pod/miner --timeout=180s >/dev/null
kubectl -n "$LAB_NS" get pod miner -o jsonpath='{.metadata.uid}' > "${STATE}/miner-uid"
info "Lab ready: Falco ${FALCO_VERSION} on node1; Namespace ${LAB_NS}."
