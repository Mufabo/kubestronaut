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
k create deployment speed --image=nginx:1.27 >/dev/null
k scale deployment speed --replicas=3 >/dev/null
k rollout status deployment/speed --timeout=180s >/dev/null

# Task 2
kubectl -n "$LAB_NS" create job count --image=busybox:1.36 --dry-run=client -o yaml -- sh -c 'echo 1' > "$LAB_JOB_FILE"
k apply -f "$LAB_JOB_FILE" >/dev/null
k wait --for=condition=Complete job/count --timeout=180s >/dev/null

# Task 3
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].restartCount}{"\n"}{end}' |
  awk '$2 > 0 {print $1}' | sort > "$LAB_RESTARTED_FILE"

# Task 4
cp "$LAB_BASE_FILE" "$LAB_SCALED_FILE"
yq -i '.spec.replicas = 5' "$LAB_SCALED_FILE"
