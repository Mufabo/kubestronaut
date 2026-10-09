# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # variables come from the sourcing script; check functions are passed by name
# Part final: timed mini-exam, Pods only, no jq/yq. Sourced by common.sh.
F1=ch03-f1
F2=ch03-f2
RED=/tmp/ch03-final-red.txt     # Task 2
GEN=/tmp/ch03-final-gen.yaml    # Task 5
IMG=/tmp/ch03-final-img.txt     # Task 6
TARGET_MINUTES=20

part_setup() {
  require_lab_cluster
  lab_teardown_ns "$F1"
  lab_teardown_ns "$F2"
  rm -f "$RED" "$GEN" "$IMG"
  mkdir -p "$STATE"
  lab_create_ns "$F1"
  lab_create_ns "$F2"
  kubectl -n "$F1" apply -f "${MANIFESTS}/final-f1-pods.yaml" >/dev/null
  kubectl -n "$F2" apply -f "${MANIFESTS}/final-f2-pods.yaml" >/dev/null
  wait_running "$F1" r1 r2 b1
  wait_running "$F2" x1 x2 x3
  jpod "$F2" x1 '{.metadata.uid}' > "${STATE}/final-x1-uid"
  date +%s > "${STATE}/final-start"       # the clock starts when setup ends
  info "Final ready. The clock is running: target ${TARGET_MINUTES} minutes. Namespaces: ${F1}, ${F2}."
}

part_verify() {
  require_lab_cluster
  t1() {
    one_container "$F1" sleeper &&
    [[ "$(jpod "$F1" sleeper '{.spec.containers[0].image}')" == "busybox:1.36" ]] &&
    [[ "$(jpod "$F1" sleeper '{.metadata.labels.team}')" == "blue" ]] &&
    [[ "$(jpod "$F1" sleeper '{.status.phase}')" == "Running" ]]
  }
  t2() {
    local rows
    rows="$(kubectl -n "$F1" get pods -o jsonpath='{range .items[*]}{.metadata.name}|{.metadata.labels.team}{"\n"}{end}')" &&
    [[ -f "$RED" && -n "$(norm_list "$RED")" ]] &&
    [[ "$(norm_list "$RED")" == "$(awk -F'|' '$2=="red"{print $1}' <<<"$rows" | sort -u)" ]]
  }
  t3() {
    local rows
    rows="$(kubectl -n "$F2" get pods -o jsonpath='{range .items[*]}{.metadata.name}|{.metadata.labels.stage}{"\n"}{end}')" &&
    [[ "$(awk -F'|' '$2=="new"{print $1}' <<<"$rows" | sort | tr '\n' ' ')" == "x1 x2 " ]] &&
    [[ "$(awk -F'|' '$1=="x3"{print $2}' <<<"$rows")" == "keep" ]]
  }
  t4() {
    [[ -f "${STATE}/final-x1-uid" ]] &&
    [[ "$(jpod "$F2" x1 '{.spec.containers[0].image}')" == "nginx:1.27" ]] &&
    [[ "$(jpod "$F2" x1 '{.metadata.uid}')" == "$(file_token "${STATE}/final-x1-uid")" ]] &&
    [[ "$(jpod "$F2" x1 '{.status.phase}')" == "Running" ]]
  }
  t5() {
    local text
    [[ -f "$GEN" ]] && text="$(<"$GEN")" &&
    [[ "$text" == *"kind: Pod"* && "$text" == *"FOO"* ]] &&
    one_container "$F2" gen &&
    [[ "$(jpod "$F2" gen '{.spec.containers[0].env[?(@.name=="FOO")].value}')" == "bar" ]] &&
    [[ "$(jpod "$F2" gen '{.status.phase}')" == "Running" ]]
  }
  t6() {
    local rows
    rows="$(kubectl -n "$F1" get pods -o jsonpath='{range .items[*]}{.metadata.name}|{.spec.containers[0].image}{"\n"}{end}')" &&
    [[ -f "$IMG" && "$(file_token "$IMG")" == "$(awk -F'|' '$2=="nginx:1.26"{print $1}' <<<"$rows" | tr -d '[:space:]')" && -n "$(file_token "$IMG")" ]]
  }
  check 1 "(${F1}) Pod sleeper: busybox:1.36, sleeps, label team=blue, one container, Running" "kubectl run ... --labels=... --command -- sleep 3600" t1
  check 2 "(${F1}) the Pods labelled team=red are listed in ${RED}" "a label selector with -o name" t2
  check 3 "(${F2}) Pods that were stage=old are now stage=new; x3 is unchanged" "kubectl label with a selector needs --overwrite to change an existing value" t3
  check 4 "(${F2}) Pod x1 runs nginx:1.27 and was NOT recreated" "kubectl set image; the container name is not the Pod name, look it up" t4
  check 5 "(${F2}) Pod gen (busybox:1.36, env FOO=bar, one container) was generated into ${GEN} and applied" "--dry-run=client -o yaml, --env, then apply" t5
  check 6 "(${F1}) the Pod that runs nginx:1.26 is named in ${IMG}" "custom-columns or JSONPath over all Pods" t6
  if [[ -f "${STATE}/final-start" ]]; then
    local now elapsed
    now="$(date +%s)"; elapsed=$((now - $(cat "${STATE}/final-start")))
    echo
    printf 'Elapsed since the lab started: %dm %02ds (target: %d minutes; time is reported, not enforced)\n' \
      $((elapsed / 60)) $((elapsed % 60)) "$TARGET_MINUTES"
  fi
}

part_solve() {
  require_lab_cluster
  local k1="kubectl -n $F1" k2="kubectl -n $F2"
  $k1 run sleeper --image=busybox:1.36 --labels=team=blue --command -- sleep 3600 >/dev/null
  $k1 get pods -l team=red -o name | sed 's#^pod/##' > "$RED"
  $k2 label pods -l stage=old stage=new --overwrite >/dev/null
  $k2 set image pod/x1 web=nginx:1.27 >/dev/null
  $k2 run gen --image=busybox:1.36 --env=FOO=bar --dry-run=client -o yaml --command -- sleep 3600 > "$GEN"
  $k2 apply -f "$GEN" >/dev/null
  $k1 get pods -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image --no-headers | awk '$2=="nginx:1.26"{print $1}' > "$IMG"
  wait_running "$F1" sleeper
  wait_running "$F2" gen
}

part_teardown() {
  require_lab_cluster
  lab_teardown_ns "$F1"
  lab_teardown_ns "$F2"
  rm -f "$RED" "$GEN" "$IMG" "${STATE}/final-start" "${STATE}/final-x1-uid"
  lab_restore_kubectx "${STATE}/kubectx"
  info "Final removed."
}
