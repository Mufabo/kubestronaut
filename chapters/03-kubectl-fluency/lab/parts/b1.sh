# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # variables come from the sourcing script; check functions are passed by name
# Part b1: context juggling. Sourced by common.sh.
NS_A=ch03-b1-a
NS_B=ch03-b1-b
CTX_A=ch03-a
CTX_B=ch03-b
OUT_A=/tmp/ch03-b1-a.txt
OUT_B=/tmp/ch03-b1-b.txt

# Make sure we are not sitting on a context we are about to delete.
leave_lab_contexts() {
  local cur
  cur="$(kubectl config current-context 2>/dev/null || true)"
  if [[ "$cur" == "$CTX_A" || "$cur" == "$CTX_B" ]]; then
    kubectl config use-context "$(base_context)" >/dev/null
  fi
}

part_setup() {
  require_lab_cluster
  lab_save_kubectx "${STATE}/kubectx"      # keeps the ORIGINAL on repeat runs
  leave_lab_contexts
  lab_delete_contexts "$CTX_A" "$CTX_B"
  lab_teardown_ns "$NS_A"
  lab_teardown_ns "$NS_B"
  rm -f "$OUT_A" "$OUT_B"
  mkdir -p "$STATE"
  random_token > "${STATE}/b1-a"
  random_token > "${STATE}/b1-b"
  lab_create_ns "$NS_A"
  lab_create_ns "$NS_B"
  kubectl -n "$NS_A" create configmap where --from-literal=value="$(cat "${STATE}/b1-a")" >/dev/null
  kubectl -n "$NS_B" create configmap where --from-literal=value="$(cat "${STATE}/b1-b")" >/dev/null
  info "Part b1 ready. Namespaces: ${NS_A}, ${NS_B}. You will create the contexts ${CTX_A} and ${CTX_B}."
}

# ctx_field <context> <field>   a field of a context from the kubeconfig
ctx_field() { kubectl config view -o "jsonpath={.contexts[?(@.name==\"$1\")].context.$2}"; }

part_verify() {
  require_lab_cluster
  local base cluster user
  base="$(base_context)"
  cluster="$(ctx_field "$base" cluster)"
  user="$(ctx_field "$base" user)"
  ctx_ok() { # ctx_ok <context> <namespace>
    [[ -n "$cluster" && -n "$user" ]] &&
    [[ "$(ctx_field "$1" namespace)" == "$2" ]] &&
    [[ "$(ctx_field "$1" cluster)" == "$cluster" ]] &&
    [[ "$(ctx_field "$1" user)" == "$user" ]]
  }
  t1() { ctx_ok "$CTX_A" "$NS_A"; }
  t2() { ctx_ok "$CTX_B" "$NS_B"; }
  t3() { [[ -f "$OUT_A" && -f "${STATE}/b1-a" && "$(file_token "$OUT_A")" == "$(file_token "${STATE}/b1-a")" ]]; }
  t4() { [[ -f "$OUT_B" && -f "${STATE}/b1-b" && "$(file_token "$OUT_B")" == "$(file_token "${STATE}/b1-b")" ]]; }
  check 1 "context ${CTX_A} exists, uses the lab cluster and user, and defaults to namespace ${NS_A}" "kubectl config set-context NAME --cluster=... --user=... --namespace=..." t1
  check 2 "context ${CTX_B} exists, uses the lab cluster and user, and defaults to namespace ${NS_B}" "copy the cluster and user from the context you are already using: kubectl config view" t2
  check 3 "the ConfigMap value read through ${CTX_A} is saved in ${OUT_A}" "kubectl --context ${CTX_A} get configmap where -o jsonpath=..." t3
  check 4 "the ConfigMap value read through ${CTX_B} is saved in ${OUT_B}" "the same ConfigMap name exists in both namespaces; the context decides which one you read" t4
}

part_solve() {
  require_lab_cluster
  local base cluster user
  base="$(base_context)"
  cluster="$(ctx_field "$base" cluster)"
  user="$(ctx_field "$base" user)"
  kubectl config set-context "$CTX_A" --cluster="$cluster" --user="$user" --namespace="$NS_A" >/dev/null
  kubectl config set-context "$CTX_B" --cluster="$cluster" --user="$user" --namespace="$NS_B" >/dev/null
  kubectl --context "$CTX_A" get configmap where -o jsonpath='{.data.value}' > "$OUT_A"
  kubectl --context "$CTX_B" get configmap where -o jsonpath='{.data.value}' > "$OUT_B"
}

part_teardown() {
  require_lab_cluster
  lab_restore_kubectx "${STATE}/kubectx"
  leave_lab_contexts
  lab_delete_contexts "$CTX_A" "$CTX_B"
  lab_teardown_ns "$NS_A"
  lab_teardown_ns "$NS_B"
  rm -f "$OUT_A" "$OUT_B" "${STATE}/b1-a" "${STATE}/b1-b"
  info "Part b1 removed; your kubectl context is restored."
}
