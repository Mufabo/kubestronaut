# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # variables come from the sourcing script; check functions are passed by name
# Part b2: imperative creation of config objects. Sourced by common.sh.
NS=ch03-b2

part_setup() {
  require_lab_cluster
  lab_teardown_ns "$NS"
  lab_create_ns "$NS"
  kubectl -n "$NS" apply -f "${MANIFESTS}/b2-pods.yaml" >/dev/null
  wait_running "$NS" web
  info "Part b2 ready. Namespace: ${NS} (use -n ${NS}, or run: make use-namespace CH=3 PART=b2)"
}

part_verify() {
  require_lab_cluster
  cm()  { kubectl -n "$NS" get configmap app-config -o "jsonpath=$1"; }
  svc() { kubectl -n "$NS" get service web -o "jsonpath=$1"; }
  t1() { [[ "$(cm '{.data.APP_MODE}')" == "prod" && "$(cm '{.data.LOG_LEVEL}')" == "info" ]]; }
  t2() {
    local enc
    enc="$(kubectl -n "$NS" get secret db-pass -o jsonpath='{.data.password}')" &&
    [[ -n "$enc" && "$(printf '%s' "$enc" | base64 -d)" == "hunter2" ]]
  }
  t3() { [[ "$(kubectl -n "$NS" get serviceaccount robot -o jsonpath='{.metadata.name}')" == "robot" ]]; }
  t4() {
    one_container "$NS" hello &&
    [[ "$(jpod "$NS" hello '{.spec.restartPolicy}')" == "Never" ]] &&
    [[ "$(jpod "$NS" hello '{.status.phase}')" == "Succeeded" ]] &&
    [[ "$(kubectl -n "$NS" logs hello)" == "hello from ch03" ]]
  }
  t5() {
    [[ "$(svc '{.spec.selector.app}')" == "web" && "$(svc '{.spec.ports[0].port}')" == "80" && "$(svc '{.spec.ports[0].targetPort}')" == "80" ]]
  }
  check 1 "ConfigMap app-config has APP_MODE=prod and LOG_LEVEL=info" "kubectl create configmap NAME --from-literal=KEY=value ..." t1
  check 2 "Secret db-pass holds password=hunter2" "kubectl create secret generic NAME --from-literal=..." t2
  check 3 "ServiceAccount robot exists" "kubectl create serviceaccount NAME" t3
  check 4 "Pod hello (one container, restartPolicy Never) ran to completion and printed 'hello from ch03'" "kubectl run ... --restart=Never -- echo ..." t4
  check 5 "a Service named web exposes Pod web on port 80 (selector app=web)" "kubectl expose pod web --port=80" t5
}

part_solve() {
  require_lab_cluster
  local k="kubectl -n $NS"
  $k create configmap app-config --from-literal=APP_MODE=prod --from-literal=LOG_LEVEL=info >/dev/null
  $k create secret generic db-pass --from-literal=password=hunter2 >/dev/null
  $k create serviceaccount robot >/dev/null
  $k run hello --image=busybox:1.36 --restart=Never -- echo "hello from ch03" >/dev/null
  $k expose pod web --port=80 >/dev/null
  wait_for "pod hello Succeeded" 180 pod_phase_is "$NS" hello Succeeded
}

part_teardown() {
  require_lab_cluster
  lab_teardown_ns "$NS"
  lab_restore_kubectx "${STATE}/kubectx"
  info "Part b2 removed."
}
