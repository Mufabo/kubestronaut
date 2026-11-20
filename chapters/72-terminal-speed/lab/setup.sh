#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
rm -f "$LAB_JOB_FILE" "$LAB_RESTARTED_FILE" "$LAB_SCALED_FILE" "$LAB_BASE_FILE"
rmdir "$LAB_ANSWER_DIR" 2>/dev/null || true
lab_create_ns "$LAB_NS"
mkdir -p "$LAB_ANSWER_DIR"

k() { kubectl -n "$LAB_NS" "$@"; }
# Three Pods for Task 3: one that keeps crashing, and two that stay up.
k run flaky --image=busybox:1.36 --restart=Always -- sh -c 'exit 1' >/dev/null
k run steady-1 --image=busybox:1.36 --restart=Always -- sleep 3600 >/dev/null
k run steady-2 --image=busybox:1.36 --restart=Always -- sleep 3600 >/dev/null
k wait --for=condition=Ready pod/steady-1 pod/steady-2 --timeout=180s >/dev/null
wait_for "flaky to restart at least once" 120 \
  bash -c "[[ \"\$(kubectl -n $LAB_NS get pod flaky -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)\" -ge 1 ]]"

# A Deployment as a base file, for Task 4. It is not created in the cluster.
cat > "$LAB_BASE_FILE" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop
spec:
  replicas: 2
  selector:
    matchLabels:
      app: shop
  template:
    metadata:
      labels:
        app: shop
    spec:
      containers:
        - name: shop
          image: nginx:1.27
YAML

info "Lab ready. Namespace: ${LAB_NS}. Pods flaky (restarting), steady-1 and steady-2. Base file ${LAB_BASE_FILE}"
