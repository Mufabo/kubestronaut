# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # variables come from lab.env; check functions are passed by name
# Part mesh: mutual TLS and identity-based authorization with Istio. The part
# installs Istio (ISTIO_VERSION, minimal profile) and removes it again on
# teardown. Sourced by common.sh.
NS=ch36-mesh
OUT=ch36-outside
API_URL=http://api.ch36-mesh:8088

# Istio's control plane with small requests, so it fits next to the other labs.
install_istio() {
  if kubectl -n istio-system get deployment istiod >/dev/null 2>&1; then
    kubectl -n istio-system rollout status deployment/istiod --timeout=300s >/dev/null
    return 0
  fi
  info "Installing Istio ${ISTIO_VERSION} (minimal profile)"
  istioctl install -y --set profile=minimal \
    --set values.pilot.resources.requests.cpu=50m --set values.pilot.resources.requests.memory=128Mi \
    --set values.global.proxy.resources.requests.cpu=10m --set values.global.proxy.resources.requests.memory=32Mi \
    >/dev/null 2>&1 || die "istioctl install failed; run it by hand to see why"
  kubectl -n istio-system rollout status deployment/istiod --timeout=300s >/dev/null
}

part_setup() {
  require_cmd istioctl
  [[ "$(istioctl version --remote=false 2>/dev/null)" == *"${ISTIO_VERSION}"* ]] ||
    die "this part needs istioctl ${ISTIO_VERSION} (versions.env); see the chapter for the install commands"
  require_lab_cluster
  lab_teardown_ns "$NS"
  lab_teardown_ns "$OUT"
  install_istio
  lab_create_ns "$NS"
  lab_create_ns "$OUT"
  kubectl -n "$NS" create serviceaccount caller >/dev/null
  kubectl -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: api
          image: busybox:1.36
          command: ["sh", "-c", "mkdir -p /www && echo ok > /www/index.html && exec httpd -f -p 8088 -h /www"]
          ports:
            - containerPort: 8088
          resources:
            requests: {cpu: 10m, memory: 16Mi}
            limits: {memory: 32Mi}
---
apiVersion: v1
kind: Service
metadata:
  name: api
spec:
  selector:
    app: api
  ports:
    - name: http
      port: 8088
      targetPort: 8088
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: client
spec:
  replicas: 1
  selector:
    matchLabels:
      app: client
  template:
    metadata:
      labels:
        app: client
    spec:
      serviceAccountName: caller
      containers:
        - name: client
          image: busybox:1.36
          command: ["sleep", "infinity"]
          resources:
            requests: {cpu: 10m, memory: 16Mi}
            limits: {memory: 32Mi}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: other
spec:
  replicas: 1
  selector:
    matchLabels:
      app: other
  template:
    metadata:
      labels:
        app: other
    spec:
      containers:
        - name: other
          image: busybox:1.36
          command: ["sleep", "infinity"]
          resources:
            requests: {cpu: 10m, memory: 16Mi}
            limits: {memory: 32Mi}
YAML
  kubectl -n "$OUT" create deployment outsider --image=busybox:1.36 -- sleep infinity >/dev/null
  local d
  for d in api client other; do kubectl -n "$NS" rollout status "deployment/${d}" --timeout=180s >/dev/null; done
  kubectl -n "$OUT" rollout status deployment/outsider --timeout=180s >/dev/null
  info "Part mesh ready: Istio ${ISTIO_VERSION} in istio-system; Namespaces ${NS} (api, client, other) and ${OUT} (outsider)."
}

part_verify() {
  require_lab_cluster
  # call <namespace> <deployment>: what its Pod gets from the api. Sets CALL_OUT.
  call() { CALL_OUT="$(kubectl -n "$1" exec "deploy/$2" -c "$2" -- wget -qO- -T 3 "$API_URL" 2>&1)"; }
  answered() { call "$1" "$2" && [[ "$CALL_OUT" == ok ]]; }
  # meshed <deployment>: rolled out, and every Pod it has carries the istio-proxy sidecar
  meshed() {
    local rows
    [[ "$(kubectl -n "$NS" get deployment "$1" -o jsonpath='{.spec.replicas}/{.status.updatedReplicas}/{.status.readyReplicas}' 2>/dev/null)" == 1/1/1 ]] || return 1
    rows="$(kubectl -n "$NS" get pods -l "app=$1" -o jsonpath='{range .items[*]}{.spec.initContainers[*].name} {.spec.containers[*].name}{"\n"}{end}' 2>/dev/null)"
    [[ -n "$rows" ]] || return 1
    ! grep -qv 'istio-proxy' <<<"$rows"
  }
  t1() {
    [[ "$(kubectl get namespace "$NS" -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null)" == enabled ]] || return 1
    meshed api && meshed client && meshed other
  }
  t2() {
    [[ "$(kubectl -n "$NS" get peerauthentication default -o jsonpath='{.spec.mtls.mode}' 2>/dev/null)" == STRICT ]] || return 1
    answered "$NS" client || return 1
    # The outsider has no sidecar, so it cannot speak mTLS: refused.
    ! answered "$OUT" outsider
  }
  t3() {
    kubectl -n "$NS" get authorizationpolicy api-allow >/dev/null 2>&1 || return 1
    answered "$NS" client || return 1
    ! call "$NS" other && [[ "$CALL_OUT" == *403* ]]
  }
  check 1 "Namespace ${NS} has sidecar injection on, and the Pods of api, client, and other carry the istio-proxy sidecar" \
    "the label istio-injection=enabled, then restart the Deployments: existing Pods are not changed" t1
  check 2 "PeerAuthentication default makes ${NS} accept only mutual TLS: client reaches the api, outsider does not" \
    "a PeerAuthentication named default in the Namespace, with spec.mtls.mode STRICT" t2
  check 3 "AuthorizationPolicy api-allow lets only workloads running as ServiceAccount caller call the api: client is answered, other gets 403" \
    "selector app=api, action ALLOW, a rule from source principals cluster.local/ns/${NS}/sa/caller" t3
}

part_solve() {
  require_lab_cluster
  local d
  # Task 1: injection on, then new Pods.
  kubectl label namespace "$NS" istio-injection=enabled --overwrite >/dev/null
  kubectl -n "$NS" rollout restart deployment api client other >/dev/null
  for d in api client other; do kubectl -n "$NS" rollout status "deployment/${d}" --timeout=180s >/dev/null; done
  one_pod_each() {
    local d2
    for d2 in api client other; do
      [[ "$(kubectl -n "$NS" get pods -l "app=${d2}" -o name | wc -l)" -eq 1 ]] || return 1
    done
  }
  wait_for "the old Pods to terminate" 120 one_pod_each

  # Tasks 2 and 3
  kubectl apply -f - >/dev/null <<YAML
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: ${NS}
spec:
  mtls:
    mode: STRICT
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-allow
  namespace: ${NS}
spec:
  selector:
    matchLabels:
      app: api
  action: ALLOW
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/${NS}/sa/caller"]
YAML
  # The sidecars receive new configuration within seconds.
  enforced() {
    local out
    out="$(kubectl -n "$OUT" exec deploy/outsider -c outsider -- wget -qO- -T 3 "$API_URL" 2>&1)" && return 1
    out="$(kubectl -n "$NS" exec deploy/other -c other -- wget -qO- -T 3 "$API_URL" 2>&1)" && return 1
    [[ "$out" == *403* ]]
  }
  wait_for "the policies to take effect" 120 enforced
}

part_teardown() {
  require_lab_cluster
  lab_teardown_ns "$NS"
  lab_teardown_ns "$OUT"
  if kubectl get namespace istio-system >/dev/null 2>&1; then
    info "Removing Istio"
    istioctl uninstall --purge -y >/dev/null 2>&1 || true
    lab_teardown_ns istio-system
  fi
  lab_restore_kubectx "${here}/.state/kubectx"
  info "Part mesh removed, with Istio."
}
