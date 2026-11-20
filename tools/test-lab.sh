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
#   6. teardown works, and leaves the cluster for the next lab (Tiers 0 and 1)
# and, across the whole run, that the lab never touches unrelated cluster state
# (sentinel namespace, ConfigMap, and ClusterRole created before the run must
# survive with the same UIDs). Exempt: Tier 0 labs (no cluster), and labs that
# rebuild the cluster on every setup (LAB_RESETS_CLUSTER=1), since the rebuild
# removes the sentinel too.
#
# A Tier 1 lab runs on the cluster profile in its LAB_PROFILE (default calico);
# if the cluster runs another one, it is rebuilt first (tools/cluster.sh), so
# labs and mocks can be tested in any order.
#
# Tier 0 labs (Part V) run in the netlab container; their read-only check
# compares a snapshot of its configured network state instead of namespaces.
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
# A Tier 2 part may start from its own snapshot (LAB_SNAPSHOT_<part>, for example
# Chapter 18's Part ha); such a lab is tested one part at a time, since only the
# host can switch snapshots.
read -r tier snap t2ctx t2name partsnaps profile resets_cluster < <(bash -c 'source "$1" 2>/dev/null
  v="LAB_SNAPSHOT_${2}"; n="$(compgen -v LAB_SNAPSHOT_ | grep -vc "^LAB_SNAPSHOT_\(NS\|CLUSTER\|NODES\)" || true)"
  printf "%s %s %s %s %s %s %s\n" "${LAB_TIER:-1}" "${!v:-${LAB_SNAPSHOT:--}}" "${LAB_CONTEXT:--}" "${LAB_CLUSTER_NAME:--}" "$n" \
    "${LAB_PROFILE:-$3}" "${LAB_RESETS_CLUSTER:-0}"' _ "${labdir}/lab/lab.env" "$only" "$LAB_DEFAULT_PROFILE")
guard_cluster=1
if [[ "$tier" == 0 ]]; then
  guard_cluster=0
elif [[ "$tier" == 2 ]]; then
  if ((partsnaps > 0)) && [[ -z "$only" ]]; then
    echo "LAB TEST FAILED (chapter ${ch}): its parts start from different snapshots; test one part: make test CH=${ch} PART=<part>" >&2
    exit 2
  fi
  require_snapshot "$snap"
  if [[ "$snap" == prereqs || "$snap" == *-prereqs ]]; then
    guard_cluster=0
  else
    LAB_TIER=2 LAB_CONTEXT="$t2ctx" LAB_CLUSTER_NAME="$t2name" require_lab_cluster
  fi
else
  have="$(kubectl --context "kind-${CLUSTER_NAME}" -n kube-system get configmap "$LAB_MARKER_NAME" -o jsonpath='{.data.profile}' 2>/dev/null || true)"
  if [[ "${have:-$LAB_DEFAULT_PROFILE}" != "$profile" ]]; then
    bash "${here}/cluster.sh" up "$profile" || fail "could not build the cluster profile '${profile}'"
  fi
  LAB_PROFILE="$profile" require_lab_cluster
  [[ "$resets_cluster" == 1 ]] && guard_cluster=0
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
# snapshot_tier0   everything a verify run must not change, normalized. Neighbour
# (ARP) caches, conntrack entries, and counters are left out on purpose:
# sending a test packet legitimately changes them.
snapshot_tier0() {
  nl_script <<'EOS'
for ns in $(ip netns list | awk '{print $1}' | sort); do
  echo "## ns ${ns}"
  # "tentative" (IPv6 duplicate address detection in progress) clears by itself.
  ip -n "$ns" -o addr show | awk '{$1=""; print}' | sed -e 's/valid_lft.*//' -e 's/ tentative//'
  # Configured state only (name, admin up/down, MTU, bridge): operational
  # state such as UNKNOWN -> UP settles by itself after a change.
  ip -n "$ns" -o link show | awk '{
    name = $2; sub(/:$/, "", name); admin = ($3 ~ /[<,]UP[,>]/) ? "up" : "down"; mtu = ""; master = ""
    for (i = 4; i < NF; i++) { if ($i == "mtu") mtu = $(i + 1); if ($i == "master") master = $(i + 1) }
    print name, admin, mtu, master }'
  ip -n "$ns" route show table all | grep -v '^local\|^broadcast\|^multicast\|fe80::' || true
  ip netns exec "$ns" sysctl -n net.ipv4.ip_forward
  ip netns exec "$ns" iptables-save 2>/dev/null | grep -v '^#' | sed 's/\[[0-9]*:[0-9]*\]//' || true
  ip netns exec "$ns" nft list ruleset 2>/dev/null | sed 's/counter packets [0-9]* bytes [0-9]*/counter/' || true
done
echo "## files"
find /root/answers /etc/netns -type f -exec md5sum {} + 2>/dev/null | sort
echo "## daemons"
ls /run/netlab 2>/dev/null | sort
EOS
}

# snapshot   Tier 0: the netlab state above. Otherwise: the lab's namespaces, the
# extra types it names, and optionally the nodes (tools/snapshot-state.sh).
snapshot() {
  if [[ "$tier" == 0 ]]; then snapshot_tier0
  else bash "${here}/snapshot-state.sh" "$ch" "$part"; fi
}

# run_verify <pass|fail> <message-if-expectation-violated>
# Runs verify, proves it changed nothing, then checks the expected outcome.
run_verify() {
  local expect=$1 msg=$2 before after rc=0
  if [[ "$snap_on" == 1 ]]; then
    before="$(snapshot)" || fail "could not snapshot the lab state"
  fi
  # When verify must pass, every question of an exam-style lab must pass too.
  if [[ "$expect" == pass ]]; then KBOOK_REQUIRE_ALL=1 run "$ch" verify "$part" || rc=$?
  else run "$ch" verify "$part" || rc=$?; fi
  if [[ "$snap_on" == 1 ]]; then
    after="$(snapshot)" || fail "could not snapshot the lab state"
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
  snap_on=1
  if [[ "$tier" != 0 ]]; then
    namespaces="$(bash "${here}/lab-namespaces.sh" snapshot "$ch" "$part")" || exit 1
    extra="$(bash -c 'source "$1"; printf "%s%s" "${LAB_SNAPSHOT_CLUSTER:-}" "${LAB_SNAPSHOT_NODES:-}"' _ "${labdir}/lab/lab.env")"
    if [[ -z "$namespaces" && -z "$extra" ]]; then
      snap_on=0
      echo "note: this lab declares no namespace (LAB_NS / LAB_SNAPSHOT_NS); the verify read-only check is skipped" >&2
    fi
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
  # Leave the cluster as the next lab expects it: a lab may change cluster-scoped
  # state (Chapter 17 taints a node), which only its teardown takes back.
  if [[ "$tier" != 2 ]]; then
    echo "### teardown";                   run "$ch" teardown "$part" || fail "teardown failed"
  fi
done
part=""
echo "LAB TEST OK (${ch})"
