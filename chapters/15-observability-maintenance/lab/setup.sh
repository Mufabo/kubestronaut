#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
rm -f "$LAB_ANSWER_FILE" "$LAB_LOG_FILE"
lab_create_ns "$LAB_NS"

k() { kubectl -n "$LAB_NS" "$@"; }

# A Deployment whose Pods log one line every two seconds.
# shellcheck disable=SC2016  # the command runs in the container, so $(date) must not expand here
k create deployment checkout --image=busybox:1.36 --replicas=2 -- \
  sh -c 'while true; do echo "order processed id=$(date +%s)"; sleep 2; done' >/dev/null

# A Pod that fails: it needs DATABASE_URL, which is not set. Its restarts give
# it a previous run with a log line to find (Task 1).
k apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: crasher
spec:
  containers:
    - name: crasher
      image: busybox:1.36
      command:
        - sh
        - -c
        - |
          if [ -z "$DATABASE_URL" ]; then
            echo "fatal: missing config DATABASE_URL"
            exit 3
          fi
          echo "connected"
          sleep 3600
YAML

k rollout status deployment/checkout --timeout=180s >/dev/null
wait_for "crasher restarted" 180 bash -c \
  "[[ \$(kubectl -n ${LAB_NS} get pod crasher -o jsonpath='{.status.containerStatuses[0].restartCount}') -ge 1 ]]"

info "Lab ready. Namespace: ${LAB_NS} (use -n ${LAB_NS}, or run: make use-namespace CH=15)"
