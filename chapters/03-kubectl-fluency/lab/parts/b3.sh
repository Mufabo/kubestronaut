# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # variables come from the sourcing script; check functions are passed by name
# Part b3: permission checks with `kubectl auth can-i`. Sourced by common.sh.
NS=ch03-b3
OUT=/tmp/ch03-b3.txt   # four lines: yes or no, in the order of the tasks
SA="system:serviceaccount:${NS}:viewer"

part_setup() {
  require_lab_cluster
  lab_teardown_ns "$NS"
  rm -f "$OUT"
  lab_create_ns "$NS"
  kubectl -n "$NS" create serviceaccount viewer >/dev/null
  kubectl -n "$NS" create rolebinding viewer-view --clusterrole=view --serviceaccount="${NS}:viewer" >/dev/null
  info "Part b3 ready. Namespace: ${NS}. The ServiceAccount is ${SA}."
}

# can <verb> <resource> <namespace>   prints yes or no ("can-i" exits 1 for no)
can() {
  local out
  out="$(kubectl auth can-i "$1" "$2" -n "$3" --as="$SA" 2>/dev/null || true)"
  printf '%s\n' "${out:-unknown}"
}
expected_answers() {
  can delete pods "$NS"
  can list secrets "$NS"
  can get pods "$NS"
  can list pods kube-system
}

part_verify() {
  require_lab_cluster
  t1() {
    local want
    want="$(expected_answers)" &&
    [[ "$want" != *unknown* && "$(wc -l <<<"$want" | tr -d '[:space:]')" == "4" ]] &&
    [[ -f "$OUT" ]] &&
    [[ "$(tr '[:upper:]' '[:lower:]' < "$OUT" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$')" == "$want" ]]
  }
  check 1 "${OUT} has four lines (yes/no) answering the four questions in the chapter text, in order" "kubectl auth can-i VERB RESOURCE -n NAMESPACE --as=${SA}" t1
}

part_solve() {
  require_lab_cluster
  expected_answers > "$OUT"
}

part_teardown() {
  require_lab_cluster
  lab_teardown_ns "$NS"
  rm -f "$OUT"
  lab_restore_kubectx "${STATE}/kubectx"
  info "Part b3 removed."
}
