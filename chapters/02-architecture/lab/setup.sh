#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
rm -f "$F_CP" "$F_ETCD" "$F_STATIC" "$F_NODE" "$F_API"

lab_create_ns "$LAB_NS"

# One Pod whose node is chosen by the scheduler at setup time (Task 4).
kubectl -n "$LAB_NS" apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: where-am-i
  labels:
    app: where-am-i
spec:
  containers:
    - name: web
      image: nginx:1.27
YAML

info "Waiting for the where-am-i Pod to be scheduled and running"
wait_for "where-am-i Running" 180 pod_phase_is "$LAB_NS" where-am-i Running

info "Lab ready. Namespace: ${LAB_NS} (use -n ${LAB_NS}, or run: make use-namespace CH=2). This lab is read-only exploration."
