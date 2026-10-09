#!/usr/bin/env bash
# Unit tests for the kubeconfig helpers in tools/lib.sh.
# Needs a `kubectl` on PATH but NO cluster: everything runs against a throwaway
# kubeconfig, so it never touches your real one.
#   tools/test-lib.sh
# shellcheck disable=SC2034  # the CHECKS_* counters are read by lib.sh functions
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export KUBECONFIG="${tmp}/config"
# shellcheck source=/dev/null
source "${here}/lib.sh"

failures=0
ok()   { printf 'ok    %s\n' "$1"; }
bad()  { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
expect() { # expect <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}
cur_ctx() { kubectl config current-context; }
cur_ns()  { kubectl config view --minify --output 'jsonpath={..namespace}'; }

fresh_kubeconfig() {
  rm -f "$KUBECONFIG"
  kubectl config set-cluster c1 --server=https://127.0.0.1:1 >/dev/null
  kubectl config set-credentials u1 --token=x >/dev/null
  kubectl config set-context orig  --cluster=c1 --user=u1 --namespace=alpha >/dev/null
  kubectl config set-context other --cluster=c1 --user=u1 >/dev/null
  kubectl config use-context orig >/dev/null
}

# 1. save, change context and namespace, restore
fresh_kubeconfig
state="${tmp}/s1"
lab_save_kubectx "$state"
kubectl config use-context other >/dev/null
kubectl config set-context --current --namespace=lab-ns >/dev/null
lab_restore_kubectx "$state" >/dev/null
expect "restore returns to the original context" "orig" "$(cur_ctx)"
expect "restore returns the original namespace" "alpha" "$(cur_ns)"
if [[ ! -f "$state" ]]; then ok "restore removes the state file"; else bad "restore removes the state file"; fi

# 2. saving twice keeps the ORIGINAL settings
fresh_kubeconfig
state="${tmp}/s2"
lab_save_kubectx "$state"
kubectl config set-context --current --namespace=changed-by-lab >/dev/null
lab_save_kubectx "$state"
lab_restore_kubectx "$state" >/dev/null
expect "second save does not overwrite the original" "alpha" "$(cur_ns)"

# 3. original context had no namespace: restore removes the one the lab set
fresh_kubeconfig
kubectl config use-context other >/dev/null
state="${tmp}/s3"
lab_save_kubectx "$state"
kubectl config set-context --current --namespace=lab-ns >/dev/null
lab_restore_kubectx "$state" >/dev/null
expect "context without a namespace ends up without one" "" "$(cur_ns)"
expect "context is unchanged" "other" "$(cur_ctx)"

# 4. delete only the named contexts; missing names are ignored
fresh_kubeconfig
kubectl config set-context ch03-a --cluster=c1 --user=u1 >/dev/null
kubectl config set-context ch03-b --cluster=c1 --user=u1 >/dev/null
lab_delete_contexts ch03-a ch03-b does-not-exist
if kubectx_exists ch03-a || kubectx_exists ch03-b; then bad "named contexts are deleted"; else ok "named contexts are deleted"; fi
if kubectx_exists orig && kubectx_exists other; then ok "other contexts are left alone"; else bad "other contexts are left alone"; fi

# 5. restore when the saved context has been deleted: warn, do not fail
fresh_kubeconfig
state="${tmp}/s5"
lab_save_kubectx "$state"
kubectl config use-context other >/dev/null
kubectl config delete-context orig >/dev/null
if lab_restore_kubectx "$state" >/dev/null 2>&1; then ok "restore tolerates a missing context"; else bad "restore tolerates a missing context"; fi
expect "current context is left unchanged in that case" "other" "$(cur_ctx)"

# 6. restore with no state file is a no-op
fresh_kubeconfig
if lab_restore_kubectx "${tmp}/never-saved" >/dev/null 2>&1; then ok "restore with nothing saved is a no-op"; else bad "restore with nothing saved is a no-op"; fi
expect "and changes nothing" "orig" "$(cur_ctx)"

# 7. check_optional never fails the lab; finish_checks reports it
CHECKS_PASSED=0; CHECKS_FAILED=0; CHECKS_OPTIONAL_DONE=0; CHECKS_OPTIONAL_TODO=0
yes_cmd() { true; }
no_cmd()  { false; }
check 1 "required ok" "h" yes_cmd >/dev/null
check_optional 2 "stretch not done" "h" no_cmd >/dev/null
check_optional 3 "stretch done" "h" yes_cmd >/dev/null
summary="$(finish_checks)"; rc=$?
expect "an undone optional task does not fail the lab" "0" "$rc"
if [[ "$summary" == *"Optional tasks done: 1 of 2"* ]]; then ok "optional progress is reported"; else bad "optional progress is reported ($summary)"; fi
CHECKS_PASSED=0; CHECKS_FAILED=0; CHECKS_OPTIONAL_DONE=0; CHECKS_OPTIONAL_TODO=0
check 1 "required fails" "h" no_cmd >/dev/null
check_optional 2 "stretch done" "h" yes_cmd >/dev/null
finish_checks >/dev/null; rc=$?
expect "a failing required task still fails the lab" "1" "$rc"

echo
if ((failures == 0)); then echo "All kubeconfig helper tests passed."; else echo "${failures} test(s) failed."; exit 1; fi
