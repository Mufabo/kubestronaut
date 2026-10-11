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

# Task 3 starts from a Pod whose init container always fails.
kubectl -n "$LAB_NS" apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: checked
spec:
  initContainers:
    - name: check
      image: busybox:1.36
      command: ["sh", "-c", "echo checking the config; exit 1"]
  containers:
    - name: main
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML

info "Lab ready. Namespace: ${LAB_NS} (use -n ${LAB_NS}, or run: make use-namespace CH=9)"
