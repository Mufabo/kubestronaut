#!/usr/bin/env bash
# Shared helpers for lab scripts. Source this file; do not execute it.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/../../../tools/lib.sh"
#
# Provides: logging, safety checks, waiting, namespace helpers, and the
# check/finish_checks framework used by every verify.sh.

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
    [[ "$marker" == "${LAB_CLUSTER_NAME:-$CLUSTER_NAME}" ]] ||
      die "this cluster is not marked as a lab cluster (ConfigMap kube-system/${LAB_MARKER_NAME} missing or wrong). If it is your disposable lab cluster, run: make cluster"
  fi
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

# ---- check framework (used by verify.sh) ------------------------------------
CHECKS_PASSED=0
CHECKS_FAILED=0

# check_optional <task-id> <description> <hint> <command...>
# Same as `check`, but a stretch task: it never makes the lab fail. Done tasks
# print PASS, not-yet-done ones print TODO with the hint.
CHECKS_OPTIONAL_DONE=0
CHECKS_OPTIONAL_TODO=0
check_optional() {
  local id=$1 desc=$2 hint=$3 rc=0; shift 3
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

# check <task-id> <description> <hint> <command...>
# The command runs in a subshell; success (exit 0) means PASS.
# It should be a function that chains conditions with && (set -e does not
# apply inside a tested command).
# Authors: run with LAB_DEBUG=1 to see a shell trace (and any kubectl error)
# of each failing check.
check() {
  local id=$1 desc=$2 hint=$3 out="" rc=0; shift 3
  if [[ "${LAB_DEBUG:-0}" == "1" ]]; then
    out="$( ( set -x; "$@" ) 2>&1 )" || rc=$?
  else
    ( "$@" ) >/dev/null 2>&1 || rc=$?
  fi
  if ((rc == 0)); then
    printf '%s\n' "${C_GRN}PASS${C_RST}  Task ${id}: ${desc}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    printf '%s\n' "${C_RED}FAIL${C_RST}  Task ${id}: ${desc}"
    printf '%s\n' "        hint: ${hint}"
    if [[ "${LAB_DEBUG:-0}" == "1" && -n "$out" ]]; then
      printf '%s\n' "        debug trace:"
      printf '%s\n' "$out" | sed 's/^/          /'
    fi
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
  fi
}

finish_checks() {
  local total=$((CHECKS_PASSED + CHECKS_FAILED)) extra=""
  if ((CHECKS_OPTIONAL_DONE + CHECKS_OPTIONAL_TODO > 0)); then
    extra=" Optional tasks done: ${CHECKS_OPTIONAL_DONE} of $((CHECKS_OPTIONAL_DONE + CHECKS_OPTIONAL_TODO))."
  fi
  echo
  if ((CHECKS_FAILED == 0)); then
    printf '%s\n' "${C_GRN}All ${total} tasks passed.${C_RST}${extra}"
    return 0
  fi
  printf '%s\n' "${C_RED}${CHECKS_PASSED}/${total} tasks passed.${C_RST}${extra}"
  return 1
}
