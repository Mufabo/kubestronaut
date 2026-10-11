#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
rm -f "$LAB_ANSWER_CIDR" "$LAB_ANSWER_IP" "$LAB_ANSWER_PROXY"
lab_create_ns "$LAB_NS"

k() { kubectl -n "$LAB_NS" "$@"; }
# A backend behind a Service, and two client Pods: one allowed later, one never.
k create deployment backend --image=nginx:1.27 --replicas=2 >/dev/null
k label deployment backend tier=api --overwrite >/dev/null
k expose deployment backend --port=80 --target-port=80 >/dev/null
k run client --image=busybox:1.36 --labels=app=client --restart=Never -- sleep 3600 >/dev/null
k run intruder --image=busybox:1.36 --labels=app=intruder --restart=Never -- sleep 3600 >/dev/null
k rollout status deployment/backend --timeout=180s >/dev/null
k wait --for=condition=Ready pod/client pod/intruder --timeout=180s >/dev/null

info "Lab ready. Namespace: ${LAB_NS}. Backend Service: backend. Clients: client (app=client), intruder (app=intruder)"
