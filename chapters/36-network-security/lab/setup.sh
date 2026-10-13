#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
rm -f "$LAB_CERT" "$LAB_KEY"
lab_create_ns "$LAB_NS"

k() { kubectl -n "$LAB_NS" "$@"; }
# A three-tier shop: frontend -> api -> db, plus a stranger that must never reach them.
# Each server is a busybox httpd that answers "ok" on its port.
serve() { # serve <name> <label> <port>
  k run "$1" --image=busybox:1.36 --labels="app=$2" --restart=Never -- \
    sh -c "mkdir -p /www && echo ok > /www/index.html && httpd -f -p $3 -h /www" >/dev/null
  k expose pod "$1" --name="$1" --port="$3" --target-port="$3" >/dev/null
}
serve api api 8080
serve db db 5432
k run frontend --image=busybox:1.36 --labels=app=frontend --restart=Never -- sleep 3600 >/dev/null
k run stranger --image=busybox:1.36 --labels=app=other --restart=Never -- sleep 3600 >/dev/null
k wait --for=condition=Ready pod/api pod/db pod/frontend pod/stranger --timeout=180s >/dev/null

# The certificate for Task 4: a self-signed one, written where the reader can find it.
mkdir -p "$LAB_CERT_DIR"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=api.ch36.example" \
  -keyout "$LAB_KEY" -out "$LAB_CERT" >/dev/null 2>&1

info "Lab ready. Namespace: ${LAB_NS}. Services: frontend, api, db, stranger. Certificate: ${LAB_CERT}"
