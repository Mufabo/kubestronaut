# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # variables come from the sourcing script; check functions are passed by name
# Part b2p: imperative creation, Pods only. Sourced by common.sh.
NS=ch03-b2p

part_setup() {
  require_lab_cluster
  lab_teardown_ns "$NS"
  lab_create_ns "$NS"
  mkdir -p "$STATE"
  kubectl -n "$NS" apply -f "${MANIFESTS}/b2p-pods.yaml" >/dev/null
  wait_running "$NS" web junk
  # Task 4 must change the image IN PLACE: remember the Pod's identity.
  jpod "$NS" web '{.metadata.uid}' > "${STATE}/b2p-web-uid"
  info "Part b2p ready. Namespace: ${NS} (use -n ${NS}, or run: make use-namespace CH=3 PART=b2p)"
}

part_verify() {
  require_lab_cluster
  t1() {
    one_container "$NS" probe &&
    [[ "$(jpod "$NS" probe '{.spec.containers[0].image}')" == "busybox:1.36" ]] &&
    [[ "$(jpod "$NS" probe '{.metadata.labels.role}')" == "probe" ]] &&
    [[ "$(jpod "$NS" probe '{.status.phase}')" == "Running" ]]
  }
  t2() {
    one_container "$NS" hello &&
    [[ "$(jpod "$NS" hello '{.spec.restartPolicy}')" == "Never" ]] &&
    [[ "$(jpod "$NS" hello '{.status.phase}')" == "Succeeded" ]] &&
    [[ "$(kubectl -n "$NS" logs hello)" == "hello from ch03" ]]
  }
  t3() {
    [[ "$(jpod "$NS" web '{.metadata.labels.tier}')" == "front" ]] &&
    [[ "$(jpod "$NS" web '{.metadata.annotations.contact}')" == "ops" ]]
  }
  t4() {
    [[ -f "${STATE}/b2p-web-uid" ]] &&
    [[ "$(jpod "$NS" web '{.spec.containers[0].image}')" == "nginx:1.27" ]] &&
    [[ "$(jpod "$NS" web '{.metadata.uid}')" == "$(file_token "${STATE}/b2p-web-uid")" ]] &&
    [[ "$(jpod "$NS" web '{.status.phase}')" == "Running" ]]
  }
  t5() {
    one_container "$NS" envpod &&
    [[ "$(jpod "$NS" envpod '{.spec.containers[0].env[?(@.name=="APP_MODE")].value}')" == "test" ]] &&
    [[ "$(jpod "$NS" envpod '{.status.phase}')" == "Running" ]]
  }
  t6() {
    local names
    names="$(kubectl -n "$NS" get pods -o jsonpath='{.items[*].metadata.name}')" &&
    word_in web "$names" && ! word_in junk "$names"
  }
  check 1 "Pod probe (busybox:1.36, label role=probe, one container) is Running" "kubectl run NAME --image=... --labels=... --command -- sleep 3600" t1
  check 2 "Pod hello ran once, printed 'hello from ch03', and was not restarted" "--restart=Never, and the command goes after --" t2
  check 3 "Pod web has label tier=front and annotation contact=ops" "kubectl label / kubectl annotate" t3
  check 4 "Pod web now runs nginx:1.27 and is the SAME Pod (not recreated)" "kubectl set image pod/web CONTAINER=IMAGE; find the container name with kubectl get pod web -o jsonpath=..." t4
  check 5 "Pod envpod has environment variable APP_MODE=test" "kubectl run has an --env flag" t5
  check 6 "Pod junk is gone and Pod web is still there" "kubectl delete pod NAME --now" t6
}

part_solve() {
  require_lab_cluster
  local k="kubectl -n $NS"
  $k run probe --image=busybox:1.36 --labels=role=probe --command -- sleep 3600 >/dev/null
  $k run hello --image=busybox:1.36 --restart=Never -- echo "hello from ch03" >/dev/null
  $k label pod web tier=front >/dev/null
  $k annotate pod web contact=ops >/dev/null
  $k set image pod/web web=nginx:1.27 >/dev/null
  $k run envpod --image=busybox:1.36 --env=APP_MODE=test --command -- sleep 3600 >/dev/null
  $k delete pod junk --now >/dev/null
  wait_for "pod hello Succeeded" 180 pod_phase_is "$NS" hello Succeeded
  wait_running "$NS" probe envpod
}

part_teardown() {
  require_lab_cluster
  lab_teardown_ns "$NS"
  rm -f "${STATE}/b2p-web-uid"
  lab_restore_kubectx "${STATE}/kubectx"
  info "Part b2p removed."
}
