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
k run web --image=nginx:1.27 --labels=app=web --port=80 >/dev/null

# Task 2
k set image pod/broken web=nginx:1.27 >/dev/null

# Task 3
k logs logger | grep -m1 'activation-code=' | cut -d= -f2 > "$LAB_ANSWER_FILE"

# Task 4
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: limited
spec:
  containers:
    - name: limited
      image: nginx:1.27
      resources:
        requests: {cpu: 100m, memory: 64Mi}
        limits: {cpu: 200m, memory: 128Mi}
YAML

# Task 5
k run once --image=busybox:1.36 --restart=Never -- echo hello >/dev/null

info "Waiting for pods to settle"
for p in web broken limited; do
  wait_for "pod $p Running" 180 pod_phase_is "$LAB_NS" "$p" Running
done
wait_for "pod once Succeeded" 120 pod_phase_is "$LAB_NS" once Succeeded
