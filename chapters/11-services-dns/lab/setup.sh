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

k() { kubectl -n "$LAB_NS" "$@"; }

# Two Deployments with running Pods, a Service whose selector is wrong (Task 5),
# and a Pod to run DNS lookups from (Task 3).
k create deployment web --image=nginx:1.27 --replicas=2 >/dev/null
k create deployment api --image=nginx:1.27 --replicas=2 >/dev/null
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: api
spec:
  selector:
    app: api-old
  ports:
    - port: 80
      targetPort: 80
YAML
k run dns-client --image=busybox:1.36 --command -- sleep 3600 >/dev/null

k rollout status deployment/web --timeout=180s >/dev/null
k rollout status deployment/api --timeout=180s >/dev/null
k wait --for=condition=Ready pod/dns-client --timeout=180s >/dev/null

info "Lab ready. Namespace: ${LAB_NS} (use -n ${LAB_NS}, or run: make use-namespace CH=11)"
