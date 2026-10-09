#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
rm -f "$LAB_ANSWER_FILE"
# Remove only this lab's own file: .state/ also holds the saved kubectl context.
mkdir -p "${here}/.state"
rm -f "${here}/.state/code" "${here}/.state/broken-uid"

lab_create_ns "$LAB_NS"

# A random code the reader must find in the logger pod's logs (Task 3).
code="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 8 || true)"
[[ ${#code} -eq 8 ]] || die "failed to generate an 8-character activation code"
printf '%s' "$code" > "${here}/.state/code"

kubectl -n "$LAB_NS" apply -f "${here}/../manifests/broken.yaml" >/dev/null
# Task 2 must fix the Pod in place: remember its identity.
kubectl -n "$LAB_NS" get pod broken -o jsonpath='{.metadata.uid}' > "${here}/.state/broken-uid"
sed "s/__CODE__/${code}/" "${here}/../manifests/logger.yaml.tpl" | kubectl -n "$LAB_NS" apply -f - >/dev/null

info "Waiting for the logger pod to start (image pull may take a moment)"
wait_for "logger pod Running" 180 pod_phase_is "$LAB_NS" logger Running
logger_printed_code() { [[ "$(kubectl -n "$LAB_NS" logs logger 2>/dev/null)" == *activation-code=* ]]; }
wait_for "logger pod printed its code" 60 logger_printed_code

info "Lab ready. Namespace: ${LAB_NS} (use -n ${LAB_NS}, or run: make use-namespace CH=4)"
