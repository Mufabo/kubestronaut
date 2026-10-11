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
k create job report --image=busybox:1.36 -- sh -c 'echo report done' >/dev/null

# Task 2
k apply -f - >/dev/null <<'YAML'
apiVersion: batch/v1
kind: Job
metadata:
  name: batch
spec:
  completions: 6
  parallelism: 2
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: busybox:1.36
          command: ["sh", "-c", "sleep 2; echo item done"]
YAML

# Task 3
k apply -f - >/dev/null <<'YAML'
apiVersion: batch/v1
kind: Job
metadata:
  name: fragile
spec:
  backoffLimit: 2
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: busybox:1.36
          command: ["sh", "-c", "echo trying; exit 1"]
YAML

# Task 4
k create cronjob nightly-report --image=busybox:1.36 --schedule="30 2 * * *" -- sh -c 'echo nightly report' >/dev/null
k patch cronjob nightly-report -p '{"spec":{"concurrencyPolicy":"Forbid","successfulJobsHistoryLimit":2}}' >/dev/null

# Task 5 (needs the CronJob from Task 4)
k create job manual-run --from=cronjob/nightly-report >/dev/null

info "Waiting for the Jobs to finish"
k wait --for=condition=Complete job/report --timeout=180s >/dev/null
k wait --for=condition=Complete job/batch --timeout=300s >/dev/null
k wait --for=condition=Complete job/manual-run --timeout=180s >/dev/null
k wait --for=condition=Failed job/fragile --timeout=300s >/dev/null
