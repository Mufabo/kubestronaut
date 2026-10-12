#!/usr/bin/env bash
# Shared helpers for lab scripts. Source this file; do not execute it.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/../../../tools/lib.sh"
#
# Provides: logging, safety checks, waiting, namespace helpers, and the
# check/check_weighted/finish_checks framework used by every verify.sh.

set -o pipefail

BOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${BOOK_ROOT}/versions.env"

if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_DIM=""; C_RST=""
fi

info() { printf '%s\n' "${C_DIM}==>${C_RST} $*"; }
warn() { printf '%s\n' "${C_YEL}warn:${C_RST} $*" >&2; }
die()  { printf '%s\n' "${C_RED}error:${C_RST} $*" >&2; exit 1; }

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"
  done
}

# Refuse to touch a cluster that is not a lab cluster. Labs delete namespaces,
# so pointing them at a real cluster by accident would be destructive.
# Two independent checks must both pass:
#   1. IDENTITY: the current context must be EXACTLY the expected one:
#        Tier 1: kind-${CLUSTER_NAME};  Tier 2: $LAB_CONTEXT
#      (a context that merely starts with "kind-" is not enough).
#   2. MARKER: the cluster must carry the ConfigMap kube-system/${LAB_MARKER_NAME}
#      whose data.cluster equals ${LAB_CLUSTER_NAME:-$CLUSTER_NAME}. `make cluster`
#      (tools/cluster.sh) creates it, so only clusters this project created,
#      or that you deliberately marked, are accepted.
# Override deliberately, at your own risk, with LAB_ALLOW_ANY_CONTEXT=1.
LAB_MARKER_NAME="${LAB_MARKER_NAME:-kbook-lab-marker}"
require_lab_cluster() {
  require_cmd kubectl
  local ctx expected marker
  ctx="$(kubectl config current-context 2>/dev/null)" || die "no kubectl context is set. Run: make cluster"
  if [[ "${LAB_ALLOW_ANY_CONTEXT:-0}" != "1" ]]; then
    expected="${LAB_CONTEXT:-kind-${CLUSTER_NAME}}"
    if [[ "$ctx" != "$expected" ]]; then
      # A lab that has the reader create contexts of their own (Chapter 03,
      # part b1) lists their names in LAB_EXTRA_CONTEXTS. Those are accepted,
      # but the marker check below still has to pass on whatever cluster they
      # point at, so they can never lead to an unmarked cluster.
      local extra ok=0
      # shellcheck disable=SC2086  # intentional word splitting of a name list
      for extra in ${LAB_EXTRA_CONTEXTS:-}; do
        [[ "$ctx" == "$extra" ]] && ok=1
      done
      ((ok)) || die "current context is '${ctx}' but this lab requires '${expected}'. Switch with: kubectl config use-context ${expected}"
    fi
  fi
  kubectl cluster-info >/dev/null 2>&1 || die "cluster for context '${ctx}' is not reachable"
  if [[ "${LAB_ALLOW_ANY_CONTEXT:-0}" != "1" ]]; then
    marker="$(kubectl -n kube-system get configmap "$LAB_MARKER_NAME" -o jsonpath='{.data.cluster}' 2>/dev/null || true)"
    if [[ "$marker" != "${LAB_CLUSTER_NAME:-$CLUSTER_NAME}" ]]; then
      if [[ "${LAB_TIER:-1}" == "2" ]]; then
        die "this cluster is not marked as the Tier 2 lab cluster (ConfigMap kube-system/${LAB_MARKER_NAME} missing or wrong). On the host, restore a cluster snapshot: envs/vagrant/kbook-vm restore cluster"
      fi
      die "this cluster is not marked as a lab cluster (ConfigMap kube-system/${LAB_MARKER_NAME} missing or wrong). If it is your disposable lab cluster, run: make cluster"
    fi
  fi
}

# require_snapshot <name>...
# Tier 2 labs run inside the VMs (envs/vagrant). Each VM records the snapshot
# it was built as in /etc/kbook/snapshot; a lab that needs a particular one
# (for example `prereqs`, where no cluster exists yet) checks it here. Only the
# host can restore snapshots, so the error says which command to run there.
KBOOK_SNAPSHOT_FILE="${KBOOK_SNAPSHOT_FILE:-/etc/kbook/snapshot}"
require_snapshot() {
  local current="" want
  [[ -r "$KBOOK_SNAPSHOT_FILE" ]] && current="$(tr -d '[:space:]' < "$KBOOK_SNAPSHOT_FILE")"
  for want in "$@"; do
    [[ "$current" == "$want" ]] && return 0
  done
  [[ -n "$current" ]] || die "this lab runs on the Tier 2 VMs (snapshot '$1'), but this machine is not one of them. Work on cp1: envs/vagrant/kbook-vm ssh"
  die "this lab needs the VM snapshot '$1', but the VMs are on '${current}'. On the host, run: envs/vagrant/kbook-vm restore $1"
}

# wait_for <description> <timeout-seconds> <command...>
wait_for() {
  local desc=$1 timeout=$2; shift 2
  local end=$((SECONDS + timeout))
  while ! "$@" >/dev/null 2>&1; do
    if ((SECONDS >= end)); then
      die "timed out after ${timeout}s waiting for: ${desc}"
    fi
    sleep 2
  done
}

# pod_phase_is <namespace> <pod> <phase>  (usable with wait_for and check)
pod_phase_is() {
  [[ "$(kubectl -n "$1" get pod "$2" -o jsonpath='{.status.phase}' 2>/dev/null)" == "$3" ]]
}

lab_teardown_ns() {
  local ns=$1
  info "Removing namespace ${ns} (if present)"
  kubectl delete namespace "$ns" --ignore-not-found --wait=true --timeout=180s >/dev/null
}

# lab_create_ns <namespace>
# Creates the namespace. It deliberately does NOT change your kubeconfig: lab
# scripts must always pass -n explicitly. Readers who want kubectl to default to
# the lab namespace opt in with `make use-namespace CH=<n>`.
lab_create_ns() {
  local ns=$1
  kubectl create namespace "$ns" >/dev/null
  info "Namespace ${ns} created"
}

# ---- kubeconfig save/restore helpers ---------------------------------------
# Labs that switch context or namespace must leave the reader's environment as
# they found it. Setup saves the original; teardown restores it.
#
#   lab_save_kubectx    "${here}/.state/kubectx"     (in setup.sh)
#   lab_restore_kubectx "${here}/.state/kubectx"     (in teardown.sh / reset.sh)
#   lab_delete_contexts ch03-a ch03-b                (contexts a lab created)

# kubectx_exists <name>
kubectx_exists() {
  local n
  while IFS= read -r n; do
    [[ "$n" == "$1" ]] && return 0
  done < <(kubectl config get-contexts -o name 2>/dev/null)
  return 1
}

# lab_save_kubectx <state-file>
# Records the current context and its default namespace. If the file already
# exists it is left alone, so repeated setups keep the reader's ORIGINAL
# settings rather than ones a previous run of the lab had changed.
lab_save_kubectx() {
  local f=$1 ctx ns
  [[ -f "$f" ]] && return 0
  ctx="$(kubectl config current-context 2>/dev/null)" || return 0
  ns="$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null || true)"
  mkdir -p "$(dirname "$f")"
  printf 'ctx=%s\nns=%s\n' "$ctx" "$ns" > "$f"
}

# lab_restore_kubectx <state-file>
# Switches back to the saved context and puts back its default namespace
# (or removes the namespace setting if there was none). Deletes the state file
# so the next setup saves fresh. Does nothing if nothing was saved.
lab_restore_kubectx() {
  local f=$1 ctx ns
  [[ -f "$f" ]] || return 0
  ctx="$(sed -n 's/^ctx=//p' "$f")"
  ns="$(sed -n 's/^ns=//p' "$f")"
  if [[ -n "$ctx" ]] && kubectx_exists "$ctx"; then
    kubectl config use-context "$ctx" >/dev/null
    if [[ -n "$ns" ]]; then
      kubectl config set-context "$ctx" --namespace="$ns" >/dev/null
    else
      kubectl config unset "contexts.${ctx}.namespace" >/dev/null 2>&1 || true
    fi
    info "Restored context ${ctx}${ns:+ and namespace ${ns}}"
  else
    warn "saved context '${ctx}' no longer exists; leaving the current context unchanged"
  fi
  rm -f "$f"
}

# lab_delete_contexts <name>...   (missing contexts are ignored)
lab_delete_contexts() {
  local n
  for n in "$@"; do
    if kubectx_exists "$n"; then
      kubectl config delete-context "$n" >/dev/null
    fi
  done
}

# ---- answer folders (exam style) ---------------------------------------------
# Exam-style labs and mock exams put answer files under
# /tmp/kbook/<lab>/<question>/, the way killer.sh and the exams use
# /opt/course/<n>/. Setup recreates the question folders empty, so readers never
# have to mkdir; teardown removes the whole lab folder.
KBOOK_COURSE_ROOT=/tmp/kbook

# course_dir_ok <dir>   true if <dir> is exactly one level below KBOOK_COURSE_ROOT
course_dir_ok() { [[ "$1" =~ ^${KBOOK_COURSE_ROOT}/[A-Za-z0-9._-]+$ && "$1" != */. && "$1" != */.. ]]; }

# lab_course_reset <dir> <question>...
lab_course_reset() {
  local dir=$1 q; shift
  course_dir_ok "$dir" || die "refusing to reset '${dir}': answer folders must be ${KBOOK_COURSE_ROOT}/<name>"
  rm -rf "$dir"
  for q in "$@"; do mkdir -p "${dir}/${q}"; done
}

# lab_course_remove <dir>
lab_course_remove() {
  course_dir_ok "$1" || die "refusing to remove '${1}': answer folders must be ${KBOOK_COURSE_ROOT}/<name>"
  rm -rf "$1"
}

# ---- check framework (used by verify.sh) ------------------------------------
# One check per task: a task is either done or not.
#   check <id> <description> <hint> <command...>          (step-by-step labs)
#   check_weighted <id> <weight> <description> <hint> <command...>
#                                                          (exam-style labs, mock exams)
#   check_optional <id> <description> <hint> <command...> (stretch task, never fails)
# A verify.sh uses either check or check_weighted, not both. Weights must add
# up to 100; finish_checks then prints the weighted score.
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_OPTIONAL_DONE=0
CHECKS_OPTIONAL_TODO=0
CHECKS_PLAIN=0
CHECKS_WEIGHTED=0
WEIGHT_TOTAL=0
WEIGHT_EARNED=0

# Step-by-step mode (tools/step.sh, `make check`): with LAB_ONLY_TASK=<id>,
# verify runs only that task's check, the way KodeKloud's Check button checks
# only the current question.
only_this_task() { [[ -z "${LAB_ONLY_TASK:-}" || "$1" == "$LAB_ONLY_TASK" ]]; }

# check_optional <task-id> <description> <hint> <command...>
# A stretch task: it never makes the lab fail. Done tasks print PASS,
# not-yet-done ones print TODO with the hint.
check_optional() {
  local id=$1 desc=$2 hint=$3 rc=0; shift 3
  only_this_task "$id" || return 0
  ( "$@" ) >/dev/null 2>&1 || rc=$?
  if ((rc == 0)); then
    printf '%s\n' "${C_GRN}PASS${C_RST}  Task ${id} (optional): ${desc}"
    CHECKS_OPTIONAL_DONE=$((CHECKS_OPTIONAL_DONE + 1))
  else
    printf '%s\n' "${C_YEL}TODO${C_RST}  Task ${id} (optional): ${desc}"
    printf '%s\n' "        hint: ${hint}"
    CHECKS_OPTIONAL_TODO=$((CHECKS_OPTIONAL_TODO + 1))
  fi
}

# _run_check <label> <description> <hint> <command...>   returns the result
# The command runs in a subshell; success (exit 0) means PASS. It should be a
# function that chains conditions with && (set -e does not apply inside a
# tested command). LAB_DEBUG=1 prints a shell trace (and any kubectl error) of
# each failing check.
_run_check() {
  local label=$1 desc=$2 hint=$3 out="" rc=0; shift 3
  if [[ "${LAB_DEBUG:-0}" == "1" ]]; then
    out="$( ( set -x; "$@" ) 2>&1 )" || rc=$?
  else
    ( "$@" ) >/dev/null 2>&1 || rc=$?
  fi
  if ((rc == 0)); then
    printf '%s\n' "${C_GRN}PASS${C_RST}  ${label}: ${desc}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
    return 0
  fi
  printf '%s\n' "${C_RED}FAIL${C_RST}  ${label}: ${desc}"
  printf '%s\n' "        hint: ${hint}"
  if [[ "${LAB_DEBUG:-0}" == "1" && -n "$out" ]]; then
    printf '%s\n' "        debug trace:"
    printf '%s\n' "$out" | sed 's/^/          /'
  fi
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  return 1
}

# check <task-id> <description> <hint> <command...>
check() {
  local id=$1; shift
  only_this_task "$id" || return 0
  CHECKS_PLAIN=$((CHECKS_PLAIN + 1))
  _run_check "Task ${id}" "$@" || true
}

# check_weighted <question-id> <weight-percent> <description> <hint> <command...>
check_weighted() {
  local id=$1 weight=$2; shift 2
  only_this_task "$id" || return 0
  CHECKS_WEIGHTED=$((CHECKS_WEIGHTED + 1))
  WEIGHT_TOTAL=$((WEIGHT_TOTAL + weight))
  if _run_check "Question ${id} (${weight}%)" "$@"; then
    WEIGHT_EARNED=$((WEIGHT_EARNED + weight))
  fi
}

# report_elapsed <start-file> <target-minutes>   time since setup finished
report_elapsed() {
  [[ -f "$1" ]] || return 0
  local elapsed=$(($(date +%s) - $(cat "$1")))
  printf 'Time used: %dm %02ds of %d minutes (reported, never enforced)\n' \
    $((elapsed / 60)) $((elapsed % 60)) "$2"
}

# finish_checks   prints the summary; exit status 0 = lab passed.
# With weights and KBOOK_PASS_PERCENT set (mock exams), the lab passes when the
# weighted score reaches the pass mark; otherwise every task must pass.
finish_checks() {
  local total=$((CHECKS_PASSED + CHECKS_FAILED)) extra=""
  if ((total + CHECKS_OPTIONAL_DONE + CHECKS_OPTIONAL_TODO == 0)); then
    # A typo in a task id must never look like a pass.
    printf '%s\n' "${C_RED}error:${C_RST} no check matched${LAB_ONLY_TASK:+ task ${LAB_ONLY_TASK}}" >&2
    return 2
  fi
  if ((CHECKS_PLAIN > 0 && CHECKS_WEIGHTED > 0)); then
    printf '%s\n' "${C_RED}error:${C_RST} verify mixes check and check_weighted; use one or the other" >&2
    return 2
  fi
  if ((CHECKS_OPTIONAL_DONE + CHECKS_OPTIONAL_TODO > 0)); then
    extra=" Optional tasks done: ${CHECKS_OPTIONAL_DONE} of $((CHECKS_OPTIONAL_DONE + CHECKS_OPTIONAL_TODO))."
  fi
  echo
  if ((CHECKS_WEIGHTED > 0)) && [[ -z "${LAB_ONLY_TASK:-}" ]]; then
    if ((WEIGHT_TOTAL != 100)); then
      printf '%s\n' "${C_RED}error:${C_RST} question weights add up to ${WEIGHT_TOTAL}%, not 100%" >&2
      return 2
    fi
    printf 'Score: %d%% (%d of %d questions)\n' "$WEIGHT_EARNED" "$CHECKS_PASSED" "$total"
    if [[ -n "${KBOOK_PASS_PERCENT:-}" ]]; then
      if ((WEIGHT_EARNED >= KBOOK_PASS_PERCENT)); then
        printf '%s\n' "${C_GRN}PASSED${C_RST} (pass mark ${KBOOK_PASS_PERCENT}%)"; return 0
      fi
      printf '%s\n' "${C_RED}NOT PASSED${C_RST} (pass mark ${KBOOK_PASS_PERCENT}%)"; return 1
    fi
  fi
  if ((CHECKS_FAILED == 0)); then
    printf '%s\n' "${C_GRN}All ${total} tasks passed.${C_RST}${extra}"
    return 0
  fi
  printf '%s\n' "${C_RED}${CHECKS_PASSED}/${total} tasks passed.${C_RST}${extra}"
  return 1
}
