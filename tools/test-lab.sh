#!/usr/bin/env bash
# CI loop for one lab (a chapter or a mock exam): every part it declares, or one.
#   test-lab.sh <chapter-number|exam-name> [part]
#
# For each part it proves that:
#   1. the untouched lab FAILS verification, and so does EVERY task on its own
#      (no task can be passed by doing nothing)
#   2. setup is idempotent (running it twice in a row works)
#   3. verify.sh is READ-ONLY (a snapshot of the lab namespace(s) is identical
#      before and after every verify run)
#   4. the reference solution PASSES verification; the tasks in the text match
#      the checks one to one; and for step-by-step labs, make check accepts
#      every task in order
#   5. reset returns the lab to a failing starting state, task by task
# and, across the whole run, that the lab never touches unrelated cluster state
# (sentinel namespace, ConfigMap, and ClusterRole created before the run must
# survive with the same UIDs).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/lib.sh"
ch="${1:?chapter number}"
only="${2:-${LAB_PART:-}}"
part=""

fail() { echo "LAB TEST FAILED (chapter ${ch}${part:+ part ${part}}): $*" >&2; exit 1; }
run()  { bash "${here}/run-lab.sh" "$@"; }

# Tier 2 labs run on the VMs (envs/vagrant). On the `prereqs` snapshot there is
# no cluster yet, so there is no cluster state to guard; and no Tier 2 lab can
# reset itself (only the host restores snapshots), so the reset phase is skipped.
labdir="$(bash "${here}/lab-path.sh" "$ch")" || exit 1
read -r tier snap t2ctx t2name < <(bash -c 'source "$1" 2>/dev/null
  printf "%s %s %s %s\n" "${LAB_TIER:-1}" "${LAB_SNAPSHOT:--}" "${LAB_CONTEXT:--}" "${LAB_CLUSTER_NAME:--}"' _ "${labdir}/lab/lab.env")
guard_cluster=1
if [[ "$tier" == 2 ]]; then
  require_snapshot "$snap"
  if [[ "$snap" == prereqs ]]; then
    guard_cluster=0
  else
    LAB_TIER=2 LAB_CONTEXT="$t2ctx" LAB_CLUSTER_NAME="$t2name" require_lab_cluster
  fi
else
  require_lab_cluster
fi

# ---- sentinel: unrelated cluster state that must survive ---------------------
SENT=kbook-sentinel
sentinel_uids() {
  printf '%s|%s|%s' \
    "$(kubectl get namespace "$SENT" -o jsonpath='{.metadata.uid}' 2>/dev/null)" \
    "$(kubectl -n "$SENT" get configmap sentinel -o jsonpath='{.metadata.uid}' 2>/dev/null)" \
    "$(kubectl get clusterrole "$SENT" -o jsonpath='{.metadata.uid}' 2>/dev/null)"
}
sentinel_cleanup() {
  kubectl delete namespace "$SENT" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true
  kubectl delete clusterrole "$SENT" --ignore-not-found >/dev/null 2>&1 || true
}
sentinel_before=""
if ((guard_cluster)); then
  trap sentinel_cleanup EXIT
  sentinel_cleanup
  kubectl create namespace "$SENT" >/dev/null || fail "could not create the sentinel namespace"
  kubectl -n "$SENT" create configmap sentinel --from-literal=purpose=must-survive >/dev/null || fail "could not create the sentinel ConfigMap"
  kubectl create clusterrole "$SENT" --verb=get --resource=pods >/dev/null || fail "could not create the sentinel ClusterRole"
  sentinel_before="$(sentinel_uids)"
  [[ "$sentinel_before" != *"||"* && "$sentinel_before" != "|"* && "$sentinel_before" != *"|" ]] ||
    fail "sentinel resources were not created properly (${sentinel_before})"
fi

# ---- helpers ------------------------------------------------------------------
snapshot() {
  # shellcheck disable=SC2086  # the namespace list is intentionally word-split
  [[ -n "$namespaces" ]] && bash "${here}/snapshot-state.sh" $namespaces
}

# run_verify <pass|fail> <message-if-expectation-violated>
# Runs verify, proves it changed nothing, then checks the expected outcome.
run_verify() {
  local expect=$1 msg=$2 before after rc=0
  if [[ -n "$namespaces" ]]; then
    before="$(snapshot)" || fail "could not snapshot namespace(s) '${namespaces}'"
  fi
  # When verify must pass, every question of an exam-style lab must pass too.
  if [[ "$expect" == pass ]]; then KBOOK_REQUIRE_ALL=1 run "$ch" verify "$part" || rc=$?
  else run "$ch" verify "$part" || rc=$?; fi
  if [[ -n "$namespaces" ]]; then
    after="$(snapshot)" || fail "could not snapshot namespace(s) '${namespaces}'"
    if [[ "$before" != "$after" ]]; then
      diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") >&2 || true
      fail "verify.sh modified cluster state; verify must be read-only"
    fi
  fi
  if [[ "$expect" == "pass" ]]; then
    ((rc == 0)) || fail "$msg"
  else
    ((rc != 0)) || fail "$msg"
    ((rc != 2)) || fail "verify reported a usage error instead of failing checks"
  fi
}

# each_task_fails   on an untouched (or reset) lab, every task must fail on its
# own, so no task can be passed by doing nothing. Optional tasks are exempt.
each_task_fails() {
  local i out rc
  for ((i = 1; ; i++)); do
    rc=0
    out="$(LAB_ONLY_TASK=$i bash "${here}/run-lab.sh" "$ch" verify "$part" 2>&1)" || rc=$?
    ((rc == 2)) && break                       # no check $i: past the last task
    [[ "$out" == *TODO* ]] && continue         # optional tasks never fail
    ((rc != 0)) || fail "task ${i} passes on the untouched lab; its check is vacuous"
  done
  ((i > 1)) || fail "verify.sh has no check 1"
}

# walk_steps   (after solve) the step-by-step runner must accept every task of
# the chapter text in order and then report the lab complete. Exam-style labs
# (Question headings) are scored all at once instead, so for them only the
# one-to-one match of text and checks is proven.
walk_steps() {
  local step="${here}/step.sh" count mode i out
  count="$(bash "$step" "$ch" count "$part")" || fail "the step runner found no tasks or questions in the text"
  mode="$(bash "$step" "$ch" mode "$part")"
  if [[ "$mode" == task ]]; then
    bash "$step" "$ch" start "$part" >/dev/null || fail "step runner: start failed"
    for ((i = 1; i <= count; i++)); do
      out="$(bash "$step" "$ch" check "$part" 2>&1)" ||
        fail "make check failed on task ${i} of ${count} after the reference solution: $(tail -n 3 <<<"$out")"
    done
    out="$(bash "$step" "$ch" check "$part" 2>&1)"
    [[ "$out" == *"Lab complete"* ]] || fail "after ${count} tasks the step runner did not report the lab complete"
    bash "$step" "$ch" clear "$part"
  else
    for ((i = 1; i <= count; i++)); do
      LAB_ONLY_TASK=$i bash "${here}/run-lab.sh" "$ch" verify "$part" >/dev/null 2>&1 ||
        fail "question ${i} of ${count} in the text has no passing check after the reference solution"
    done
  fi
  # A check beyond the last task in the text would never be shown to readers.
  out="$(LAB_ONLY_TASK=$((count + 1)) bash "${here}/run-lab.sh" "$ch" verify "$part" 2>&1)" &&
    fail "verify.sh has more checks than the text has tasks (check $((count + 1)) exists)"
  return 0
}

parts="$(bash "${here}/lab-parts.sh" "$ch")" || exit 1
if [[ -n "$only" ]]; then
  list=("$only")
elif [[ -n "$parts" ]]; then
  read -ra list <<<"$parts"
else
  list=("")
fi

for part in "${list[@]}"; do
  echo "=== ${ch}${part:+ part ${part}} ==="
  namespaces="$(bash "${here}/lab-namespaces.sh" snapshot "$ch" "$part")" || exit 1
  if [[ -z "$namespaces" ]]; then
    echo "note: this lab declares no namespace (LAB_NS / LAB_SNAPSHOT_NS); the verify read-only check is skipped" >&2
  fi
  echo "### setup";                      run "$ch" setup "$part" || fail "setup failed"
  echo "### setup again (idempotency)";  run "$ch" setup "$part" || fail "second setup failed"
  echo "### verify on starting state (must fail, must not change anything)"
  run_verify fail "verify passed on the untouched lab"
  echo "### every task fails on its own on the starting state"
  each_task_fails
  echo "### solve";                      run "$ch" solve "$part" || fail "solve failed"
  echo "### verify after solve (must pass, must not change anything)"
  run_verify pass "verify failed after the reference solution"
  echo "### text and checks line up (step labs: make check passes every task in order)"
  walk_steps
  if [[ "$tier" == 2 ]]; then
    echo "### reset: skipped (Tier 2: restore snapshot ${snap} on the host, then run setup and verify to check the starting state)"
  else
    echo "### reset";                      run "$ch" reset "$part" || fail "reset failed"
    echo "### verify after reset (must fail, every task on its own)"
    run_verify fail "verify passed after reset"
    each_task_fails
  fi
  if ((guard_cluster)); then
    [[ "$(sentinel_uids)" == "$sentinel_before" ]] ||
      fail "the lab changed or deleted unrelated cluster state (sentinel resources differ)"
  fi
done
part=""
echo "LAB TEST OK (${ch})"
