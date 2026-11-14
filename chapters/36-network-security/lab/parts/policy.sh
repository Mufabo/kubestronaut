# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # variables come from lab.env; check functions are passed by name
# Part policy: NetworkPolicies and a TLS Secret in ch36-shop (the original lab).
# Sourced by common.sh.

part_setup() {
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
}

part_verify() {
require_lab_cluster

k() { kubectl -n "$LAB_NS" "$@"; }
jp() { k get "$1" -o "jsonpath=$2" 2>/dev/null; }

# fetch <from-pod> <url>: what the Pod gets back. Sets FETCH_OUT, returns the status.
fetch() {
  FETCH_OUT="$(k exec "$1" -- wget -q -T 3 -O- "$2" 2>&1)"
}
# reachable <from-pod> <url>: the request is answered with "ok"
reachable() { fetch "$1" "$2" && [[ "$FETCH_OUT" == *ok* ]]; }
# blocked <from-pod> <url>: the request times out, as a policy drop does. A DNS failure
# is not a block, so it does not count.
blocked() { ! fetch "$1" "$2" && [[ "$FETCH_OUT" == *"timed out"* ]]; }
# resolves <from-pod> <name>: the Pod's DNS returns an answer for the name
resolves() { [[ "$(k exec "$1" -- nslookup "$2" 2>&1)" == *"Name:"* ]]; }

t1() {
  [[ "$(jp networkpolicy/default-deny '{.spec.podSelector}')" == '{}' ]] &&
  [[ "$(jp networkpolicy/default-deny '{.spec.policyTypes}')" == '["Ingress","Egress"]' ]] &&
  [[ "$(jp networkpolicy/allow-dns '{.spec.policyTypes}')" == '["Egress"]' ]] &&
  [[ "$(jp networkpolicy/allow-dns '{.spec.egress[0].ports[*].port}')" == "53 53" ]] &&
  blocked stranger http://api:8080/ &&
  resolves stranger api
}

t2() {
  [[ "$(jp networkpolicy/frontend-to-api '{.spec.podSelector.matchLabels.app}')" == frontend ]] &&
  [[ "$(jp networkpolicy/frontend-to-api '{.spec.egress[0].to[0].podSelector.matchLabels.app}')" == api ]] &&
  [[ "$(jp networkpolicy/frontend-to-api '{.spec.egress[0].ports[0].port}')" == 8080 ]] &&
  [[ "$(jp networkpolicy/api-from-frontend '{.spec.podSelector.matchLabels.app}')" == api ]] &&
  [[ "$(jp networkpolicy/api-from-frontend '{.spec.ingress[0].from[0].podSelector.matchLabels.app}')" == frontend ]] &&
  [[ "$(jp networkpolicy/api-from-frontend '{.spec.ingress[0].ports[0].port}')" == 8080 ]] &&
  reachable frontend http://api:8080/ && blocked stranger http://api:8080/
}

t3() {
  [[ "$(jp networkpolicy/api-to-db '{.spec.podSelector.matchLabels.app}')" == api ]] &&
  [[ "$(jp networkpolicy/api-to-db '{.spec.egress[0].to[0].podSelector.matchLabels.app}')" == db ]] &&
  [[ "$(jp networkpolicy/api-to-db '{.spec.egress[0].ports[0].port}')" == 5432 ]] &&
  [[ "$(jp networkpolicy/db-from-api '{.spec.podSelector.matchLabels.app}')" == db ]] &&
  [[ "$(jp networkpolicy/db-from-api '{.spec.ingress[0].from[0].podSelector.matchLabels.app}')" == api ]] &&
  [[ "$(jp networkpolicy/db-from-api '{.spec.ingress[0].ports[0].port}')" == 5432 ]] &&
  reachable api http://db:5432/ && blocked frontend http://db:5432/
}

t4() {
  [[ "$(jp secret/api-tls '{.type}')" == kubernetes.io/tls ]] || return 1
  [[ -s "$LAB_CERT" && -s "$LAB_KEY" ]] || return 1
  [[ "$(jp secret/api-tls '{.data.tls\.crt}' | base64 -d)" == "$(cat "$LAB_CERT")" ]] &&
  [[ "$(jp secret/api-tls '{.data.tls\.key}' | base64 -d)" == "$(cat "$LAB_KEY")" ]]
}

check 1 "A default deny for ingress and egress, with DNS allowed, blocks the stranger from the api, and DNS still resolves" \
  "networkpolicy default-deny: empty podSelector, policyTypes Ingress and Egress; allow-dns: egress to port 53, UDP and TCP" t1
check 2 "The frontend reaches the api on port 8080, and the stranger does not" \
  "both ends need a policy: an egress rule on the frontend and an ingress rule on the api" t2
check 3 "The api reaches the db on port 5432, and the frontend does not" \
  "both ends need a policy: an egress rule on the api and an ingress rule on the db" t3
check 4 "Secret api-tls is a TLS Secret holding the certificate and key in ${LAB_CERT_DIR}" \
  "kubectl create secret tls api-tls --cert=... --key=... in the lab Namespace" t4
}

part_solve() {
require_lab_cluster

k() { kubectl -n "$LAB_NS" "$@"; }

# Task 1
k apply -f - >/dev/null <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes: ["Ingress", "Egress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
spec:
  podSelector: {}
  policyTypes: ["Egress"]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
YAML

# Task 2
k apply -f - >/dev/null <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-to-api
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes: ["Egress"]
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: api
      ports:
        - port: 8080
          protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-from-frontend
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - port: 8080
          protocol: TCP
YAML

# Task 3
k apply -f - >/dev/null <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-to-db
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: ["Egress"]
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: db
      ports:
        - port: 5432
          protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-from-api
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api
      ports:
        - port: 5432
          protocol: TCP
YAML

# Task 4
k create secret tls api-tls --cert="$LAB_CERT" --key="$LAB_KEY" >/dev/null
}

part_teardown() {
require_lab_cluster
lab_teardown_ns "$LAB_NS"
rm -f "$LAB_CERT" "$LAB_KEY"
rmdir "$LAB_CERT_DIR" 2>/dev/null || true
lab_restore_kubectx "${here}/.state/kubectx"
info "Lab removed."
}
