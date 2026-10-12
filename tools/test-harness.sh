#!/usr/bin/env bash
# Tests for the lab FRAMEWORK itself, using a fake kubectl (no cluster needed).
# Proves that the safety checks refuse unsafe clusters, that the test loop
# catches the ways a lab can be wrong (vacuous checks, mutating verify, damage to
# unrelated resources), and that kubeconfig changes are opt-in and undoable.
#   tools/test-harness.sh
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'ok    %s\n' "$1"; }
flunk() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# ---- sandbox: a copy of the tooling plus fixture chapters ---------------------
sb="${work}/repo"
mkdir -p "${sb}/chapters" "${work}/bin"
cp -r "${root}/tools" "${root}/versions.env" "${root}/Makefile" "$sb"/
printf '#!/bin/sh\nexec python3 "%s/tools/testdata/fake-kubectl.py" "$@"\n' "$root" > "${work}/bin/kubectl"
chmod +x "${work}/bin/kubectl"
export PATH="${work}/bin:${PATH}"
export FAKE_KUBE_STATE="${work}/state.json"

# fresh_state <current-context> <marker-value or ""> [original-namespace]
fresh_state() {
  python3 - "$FAKE_KUBE_STATE" "$1" "$2" "${3:-orig}" <<'PY'
import json, sys
path, ctx, marker, ns = sys.argv[1:5]
cms = {"kbook-lab-marker": {"uid": "uid-m", "data": {"cluster": marker}}} if marker else {}
json.dump({
    "n": 1, "current": ctx,
    "contexts": {"kind-kbook": {"namespace": ns, "cluster": "kind-kbook", "user": "kind-kbook"},
                 "kind-production": {"namespace": ns, "cluster": "kind-production", "user": "kind-production"}},
    "namespaces": {"kube-system": {"uid": "uid-0", "configmaps": cms}, "default": {"uid": "uid-d", "configmaps": {}}},
    "clusterroles": {},
}, open(path, "w"))
PY
}
state_has() { # state_has <python-expression over st>
  python3 -c "import json,sys; st=json.load(open('$FAKE_KUBE_STATE')); sys.exit(0 if ($1) else 1)"
}
cur_ns() { kubectl config view --minify --output 'jsonpath={..namespace}'; }

# make_lab <NN> <slug> <mode> [parts]     modes: good | vacuous | mutating | killer
# shellcheck disable=SC2016  # the generated scripts must keep their $variables literal
make_lab() {
  local nn=$1 slug=$2 mode=$3 parts=${4:-} d
  d="${sb}/chapters/${nn}-${slug}/lab"
  mkdir -p "$d"
  # The chapter text: one task per lab (or part); mode "extratask" has two.
  {
    printf '# Chapter %s\n\n## Hands-on lab\n\n' "$nn"
    if [[ -n "$parts" ]]; then
      local p; for p in $parts; do printf '### Part %s: fixture\n\n#### Task 1: Answer\n\nCreate it.\n\n' "$p"; done
    else
      if [[ "$mode" == examq ]]; then
        printf '### Question 1 | Answer\n\nTask weight: 100%%\n\nCreate ConfigMap answer.\n\n'
      else
        printf '### Task 1: Answer\n\nCreate ConfigMap answer.\n\n'
      fi
      [[ "$mode" == extratask ]] && printf '### Task 2: Extra\n\nThis task has no check.\n\n'
      [[ "$mode" == lazytask ]] && printf '### Task 2: Free\n\nNothing to do.\n\n'
    fi
    printf '## Exam tips\n\n### Task 9: not a lab task\n'
  } > "${d}/../${nn}-${slug}.md"
  {
    echo "LAB_TIER=9"
    if [[ -n "$parts" ]]; then
      echo "LAB_PARTS=\"${parts}\""
      local p; for p in $parts; do echo "LAB_NS_${p}=fx-${nn}-${p}"; done
    else
      echo "LAB_NS=fx-${nn}"
    fi
  } > "${d}/lab.env"
  local pre='set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${here}/../../../tools/lib.sh"
source "${here}/lab.env"
require_lab_cluster
ns_var="LAB_NS_${LAB_PART:-}"; ns="${!ns_var:-${LAB_NS:-}}"'
  local kill=""
  [[ "$mode" == killer ]] && kill='kubectl delete namespace kbook-sentinel --ignore-not-found >/dev/null'
  printf '#!/usr/bin/env bash\n%s\nlab_teardown_ns "$ns"\nlab_create_ns "$ns"\nkubectl -n "$ns" create configmap seed --from-literal=a=b >/dev/null\n%s\n' "$pre" "$kill" > "${d}/setup.sh"
  printf '#!/usr/bin/env bash\nexec bash "$(dirname "${BASH_SOURCE[0]}")/setup.sh"\n' > "${d}/reset.sh"
  printf '#!/usr/bin/env bash\n%s\nkubectl -n "$ns" create configmap answer --from-literal=v=1 >/dev/null\n' "$pre" > "${d}/solve.sh"
  printf '#!/usr/bin/env bash\n%s\nlab_teardown_ns "$ns"\nlab_restore_kubectx "${here}/.state/kubectx"\n' "$pre" > "${d}/teardown.sh"
  case "$mode" in
    vacuous)  printf '#!/usr/bin/env bash\nexit 0\n' > "${d}/verify.sh" ;;
    lazytask) printf '#!/usr/bin/env bash\nset -uo pipefail\n%s\nanswered() { kubectl -n "$ns" get configmap answer -o jsonpath="{.metadata.uid}"; }\ncheck 1 "answer exists" "create configmap answer" answered\ncheck 2 "always true" "nothing to do" true\nfinish_checks\n' "${pre/set -euo pipefail/}" > "${d}/verify.sh" ;;
    examq) printf '#!/usr/bin/env bash\nset -uo pipefail\n%s\nanswered() { kubectl -n "$ns" get configmap answer -o jsonpath="{.metadata.uid}"; }\ncheck_weighted 1 100 "answer exists" "create configmap answer" answered\nfinish_checks\n' "${pre/set -euo pipefail/}" > "${d}/verify.sh" ;;
    extracheck) printf '#!/usr/bin/env bash\nset -uo pipefail\n%s\nanswered() { kubectl -n "$ns" get configmap answer -o jsonpath="{.metadata.uid}"; }\ncheck 1 "answer exists" "create configmap answer" answered\ncheck 2 "answer still exists" "no task asks for this" answered\nfinish_checks\n' "${pre/set -euo pipefail/}" > "${d}/verify.sh" ;;
    mutating) printf '#!/usr/bin/env bash\nset -uo pipefail\n%s\nkubectl -n "$ns" create configmap oops --from-literal=x=y >/dev/null 2>&1 || true\nanswered() { kubectl -n "$ns" get configmap answer -o jsonpath="{.metadata.uid}"; }\ncheck 1 "answer exists" "create it" answered\nfinish_checks\n' "${pre/set -euo pipefail/}" > "${d}/verify.sh" ;;
    *)        printf '#!/usr/bin/env bash\nset -uo pipefail\n%s\nanswered() { kubectl -n "$ns" get configmap answer -o jsonpath="{.metadata.uid}"; }\ncheck 1 "answer exists" "create configmap answer" answered\nfinish_checks\n' "${pre/set -euo pipefail/}" > "${d}/verify.sh" ;;
  esac
}
in_sb() { ( cd "$sb" && "$@" ); }
# expect <description> <expected-exit: 0|nonzero> <output-must-contain or ""> -- <cmd...>
expect() {
  local desc=$1 want=$2 needle=$3; shift 4
  local out rc=0
  out="$(in_sb "$@" 2>&1)" || rc=$?
  if [[ "$want" == 0 && $rc -ne 0 ]] || [[ "$want" != 0 && $rc -eq 0 ]]; then
    flunk "$desc (exit ${rc})"; printf '%s\n' "$out" | tail -5 | sed 's/^/        /'; return
  fi
  if [[ -n "$needle" && "$out" != *"$needle"* ]]; then
    flunk "$desc (output lacks: ${needle})"; printf '%s\n' "$out" | tail -5 | sed 's/^/        /'; return
  fi
  pass "$desc"
}

make_lab 90 good good "p q"
make_lab 91 vacuous vacuous
make_lab 92 mutating mutating
make_lab 93 killer killer
make_lab 94 single good
make_lab 95 extratask extratask
make_lab 96 extracheck extracheck
make_lab 97 lazytask lazytask
make_lab 98 examq examq

# ---- safety ---------------------------------------------------------------------
fresh_state kind-production kbook
expect "a lookalike or production context is refused" nonzero "requires 'kind-kbook'" -- bash tools/run-lab.sh 94 setup
fresh_state kind-kbook ""
expect "a cluster without the lab marker is refused" nonzero "not marked as a lab cluster" -- bash tools/run-lab.sh 94 setup
fresh_state kind-kbook someone-elses-cluster
expect "a marker naming a different cluster is refused" nonzero "not marked as a lab cluster" -- bash tools/run-lab.sh 94 setup
fresh_state kind-production ""
expect "LAB_ALLOW_ANY_CONTEXT=1 is the explicit override" 0 "" -- env LAB_ALLOW_ANY_CONTEXT=1 bash tools/run-lab.sh 94 setup
fresh_state kind-kbook kbook
expect "the right context plus marker is accepted" 0 "" -- bash tools/run-lab.sh 94 setup

# ---- the test loop catches bad labs ---------------------------------------------
fresh_state kind-kbook kbook
expect "a correct multi-part lab passes the loop (all parts)" 0 "LAB TEST OK" -- bash tools/test-lab.sh 90
if state_has "'kbook-sentinel' not in st['namespaces'] and 'kbook-sentinel' not in st['clusterroles']"; then pass "sentinels are cleaned up after a passing run"; else flunk "sentinels are cleaned up after a passing run"; fi
expect "a single part can be tested" 0 "part q" -- bash tools/test-lab.sh 90 q
fresh_state kind-kbook kbook
expect "a vacuous verify.sh is caught" nonzero "untouched lab" -- bash tools/test-lab.sh 91
fresh_state kind-kbook kbook
expect "a verify.sh that changes state is caught" nonzero "must be read-only" -- bash tools/test-lab.sh 92
if state_has "'kbook-sentinel' not in st['namespaces'] and 'kbook-sentinel' not in st['clusterroles']"; then pass "sentinels are cleaned up after a failing run"; else flunk "sentinels are cleaned up after a failing run"; fi
fresh_state kind-kbook kbook
expect "a lab that destroys unrelated state is caught" nonzero "unrelated cluster state" -- bash tools/test-lab.sh 93
fresh_state kind-kbook kbook
expect "a chapter text with a task that has no check is caught" nonzero "make check failed on task 2" -- bash tools/test-lab.sh 95
fresh_state kind-kbook kbook
expect "a check that no task in the text asks for is caught" nonzero "more checks than the text has tasks" -- bash tools/test-lab.sh 96
fresh_state kind-kbook kbook
expect "a single task that passes on the untouched lab is caught" nonzero "task 2 passes on the untouched lab" -- bash tools/test-lab.sh 97
fresh_state kind-kbook kbook
expect "an exam-style lab passes the loop" 0 "LAB TEST OK" -- bash tools/test-lab.sh 98

# ---- scoring: one check per task; weights for exam style ---------------------------
expect "weighted questions print a score" nonzero "Score: 60% (1 of 2 questions)" -- \
  bash -c 'source tools/lib.sh; check_weighted 1 60 A h true; check_weighted 2 40 B h false; finish_checks'
expect "a pass mark lets a mock exam pass without every question" 0 "PASSED (pass mark 60%)" -- \
  env KBOOK_PASS_PERCENT=60 bash -c 'source tools/lib.sh; check_weighted 1 60 A h true; check_weighted 2 40 B h false; finish_checks'
expect "below the pass mark a mock exam fails" nonzero "NOT PASSED" -- \
  env KBOOK_PASS_PERCENT=66 bash -c 'source tools/lib.sh; check_weighted 1 60 A h true; check_weighted 2 40 B h false; finish_checks'
expect "weights that do not add up to 100 are an error" nonzero "add up to 90%" -- \
  bash -c 'source tools/lib.sh; check_weighted 1 90 A h true; finish_checks'
expect "mixing check and check_weighted is an error" nonzero "mixes check and check_weighted" -- \
  bash -c 'source tools/lib.sh; check 1 A h true; check_weighted 2 100 B h true; finish_checks'
expect "one weighted question can be checked on its own" 0 "PASS  Question 1" -- \
  env KBOOK_PASS_PERCENT=66 LAB_ONLY_TASK=1 bash -c 'source tools/lib.sh; check_weighted 1 60 A h true; check_weighted 2 40 B h false; finish_checks'
expect "answer folders outside /tmp/kbook are refused" nonzero "refusing" -- \
  bash -c 'source tools/lib.sh; lab_course_reset /tmp 1'
expect "answer folders must be one level below /tmp/kbook" nonzero "refusing" -- \
  bash -c 'source tools/lib.sh; lab_course_remove /tmp/kbook'

# ---- Tier 2: VM snapshots ------------------------------------------------------------
snapfile="${work}/kbook-snapshot"
printf 'cluster\n' > "$snapfile"
expect "require_snapshot accepts the snapshot the VMs are on" 0 "" -- \
  env KBOOK_SNAPSHOT_FILE="$snapfile" bash -c 'source tools/lib.sh; require_snapshot cluster'
expect "require_snapshot accepts any of several snapshots" 0 "" -- \
  env KBOOK_SNAPSHOT_FILE="$snapfile" bash -c 'source tools/lib.sh; require_snapshot prereqs cluster'
expect "require_snapshot names the host command for the wrong snapshot" nonzero "kbook-vm restore prereqs" -- \
  env KBOOK_SNAPSHOT_FILE="$snapfile" bash -c 'source tools/lib.sh; require_snapshot prereqs'
expect "require_snapshot refuses a machine that is not a Tier 2 VM" nonzero "not one of them" -- \
  env KBOOK_SNAPSHOT_FILE="${work}/no-such-file" bash -c 'source tools/lib.sh; require_snapshot cluster'
mkdir -p "${sb}/chapters/89-tiertwo/lab"
printf '### Task 1: x\n' > "${sb}/chapters/89-tiertwo/89-tiertwo.md"
printf 'LAB_TIER=2\nLAB_SNAPSHOT=cluster-prev\n' > "${sb}/chapters/89-tiertwo/lab/lab.env"
printf '#!/usr/bin/env bash\necho reset ran\n' > "${sb}/chapters/89-tiertwo/lab/reset.sh"
expect "a Tier 2 reset points to the host's snapshot restore instead of running" nonzero "kbook-vm restore cluster-prev" -- \
  bash tools/run-lab.sh 89 reset
out="$(in_sb bash tools/run-lab.sh 89 reset 2>&1)"
if [[ "$out" != *"reset ran"* ]]; then pass "a Tier 2 reset never runs reset.sh"; else flunk "a Tier 2 reset never runs reset.sh"; fi

# ---- exam style and mock exams ------------------------------------------------------
fresh_state kind-kbook kbook
in_sb bash tools/run-lab.sh 98 setup >/dev/null 2>&1
expect "an exam-style lab shows the exam banner, not a task" 0 "Exam style: 1 questions" -- bash tools/step.sh 98 start
expect "an exam-style lab has no per-question check" nonzero "no per-question checks" -- bash tools/step.sh 98 check
mkdir -p "${sb}/mock-exams/zz-mock/lab"
printf '# Mock\n\n## Question 1 | One\n\nTask weight: 100%%\n' > "${sb}/mock-exams/zz-mock/zz-mock.md"
expect "a mock exam is found by its name" 0 "mock-exams/zz-mock" -- bash tools/lab-path.sh zz-mock
expect "a mock exam's questions are read from its file" 0 "question" -- bash tools/step.sh zz-mock mode
expect "an unknown mock exam name is an error" nonzero "neither a chapter number nor a mock exam" -- bash tools/lab-path.sh nope

# ---- step by step (KodeKloud style) ------------------------------------------------
fresh_state kind-kbook kbook
in_sb bash tools/run-lab.sh 94 setup >/dev/null 2>&1
expect "starting a lab shows task 1 from the chapter text" 0 "Task 1 of 1" -- bash tools/step.sh 94 start
expect "the task text is printed" 0 "Create ConfigMap answer." -- bash tools/step.sh 94 question
expect "checking an unsolved task says not yet, with the hint" nonzero "create configmap answer" -- bash tools/step.sh 94 check
in_sb bash tools/run-lab.sh 94 solve >/dev/null 2>&1
expect "checking a solved task says correct" 0 "Correct!" -- bash tools/step.sh 94 check
expect "after the last task the lab is complete" 0 "Lab complete" -- bash tools/step.sh 94 question
if [[ "$(in_sb bash tools/step.sh 94 count)" == 1 ]]; then pass "headings outside the lab section are not tasks"; else flunk "headings outside the lab section are not tasks"; fi
expect "each part reads its own tasks" 0 "Task 1 of 1" -- bash tools/step.sh 90 start q
expect "an unknown part is a usage error for the runner too" nonzero "unknown part" -- bash tools/step.sh 90 start zzz
expect "a check id that does not exist is an error, not a pass" nonzero "no check matched" -- env LAB_ONLY_TASK=7 bash tools/run-lab.sh 94 verify
in_sb bash tools/step.sh 94 clear
if [[ ! -f "${sb}/chapters/94-single/lab/.state/step" ]]; then pass "clearing forgets the progress"; else flunk "clearing forgets the progress"; fi

# ---- part handling -----------------------------------------------------------------
fresh_state kind-kbook kbook
expect "an unknown part is a usage error (exit 2)" nonzero "unknown part" -- bash tools/run-lab.sh 90 setup zzz
expect "a part on a chapter without parts is rejected" nonzero "has no parts" -- bash tools/run-lab.sh 94 setup zzz
rm -f "${sb}/chapters/91-vacuous/lab/teardown.sh"
expect "a lab without a teardown script is a friendly no-op" 0 "nothing to do" -- bash tools/run-lab.sh 91 teardown

# ---- kubeconfig is not touched implicitly; opt-in is undoable -----------------
fresh_state kind-kbook kbook alpha
in_sb bash tools/run-lab.sh 90 setup p >/dev/null 2>&1
if [[ "$(cur_ns)" == "alpha" ]]; then pass "make lab does not change your default namespace"; else flunk "make lab does not change your default namespace (now '$(cur_ns)')"; fi
in_sb bash tools/run-lab.sh 90 use-namespace p >/dev/null 2>&1
if [[ "$(cur_ns)" == "fx-90-p" ]]; then pass "use-namespace opts in to the lab namespace"; else flunk "use-namespace opts in (now '$(cur_ns)')"; fi
in_sb bash tools/run-lab.sh 90 setup p >/dev/null 2>&1
in_sb bash tools/run-lab.sh 90 use-namespace p >/dev/null 2>&1
in_sb bash tools/run-lab.sh 90 teardown p >/dev/null 2>&1
if [[ "$(cur_ns)" == "alpha" ]]; then pass "teardown restores your original namespace (even after repeated use-namespace)"; else flunk "teardown restores your original namespace (now '$(cur_ns)')"; fi
if state_has "'fx-90-p' not in st['namespaces']"; then pass "teardown removes the lab namespace"; else flunk "teardown removes the lab namespace"; fi

# ---- diagnostics ----------------------------------------------------------------------
fresh_state kind-kbook kbook
in_sb bash tools/run-lab.sh 90 setup p >/dev/null 2>&1
expect "LAB_DEBUG=1 shows a trace for failing checks" nonzero "debug trace" -- env LAB_DEBUG=1 bash tools/run-lab.sh 90 verify p
expect "without LAB_DEBUG the output stays clean" nonzero "hint:" -- bash tools/run-lab.sh 90 verify p
out="$(in_sb bash tools/run-lab.sh 90 verify p 2>&1)"; if [[ "$out" == *"debug trace"* ]]; then flunk "no trace without LAB_DEBUG"; else pass "no trace without LAB_DEBUG"; fi

# ---- chapter lookup and CI guards -----------------------------------------------------
mkdir -p "${sb}/chapters/94-single-old"
expect "an ambiguous chapter number is an error" nonzero "ambiguous" -- bash tools/lab-path.sh 94
rmdir "${sb}/chapters/94-single-old"
expect "an unknown chapter number is an error" nonzero "no chapter directory" -- bash tools/lab-path.sh 77
empty="${work}/empty"; mkdir -p "${empty}/chapters"; cp -r "${root}/tools" "${root}/versions.env" "${root}/Makefile" "$empty"/
expect "make test-tier1 fails when there are no Tier 1 labs" nonzero "no Tier 1 labs" -- make -C "$empty" test-tier1

# ---- the real Chapter 03 lab scripts against the fake kubectl ------------------------
# (This exercises the scripts' logic. Real kubectl behaviour is CI's job.)
# NOTE: the lab writes its answer files under /tmp/ch03-*; this section removes them.
cp -r "${root}/chapters/03-kubectl-fluency" "${sb}/chapters/"
# The copy starts from a clean state: a .state folder left by an earlier run of
# the real lab (a saved kubeconfig, for example) must not leak into these tests.
rm -rf "${sb}/chapters/03-kubectl-fluency/lab/.state"
rm -f /tmp/ch03-*.txt /tmp/ch03-*.yaml
fresh_state kind-kbook kbook alpha
expect "chapter 3: all six parts pass the full loop" 0 "LAB TEST OK" -- bash tools/test-lab.sh 3

verify_out() { in_sb bash tools/run-lab.sh 3 verify "$1" 2>&1; }
runlab()     { in_sb bash tools/run-lab.sh 3 "$@" >/dev/null 2>&1; }
kc()         { kubectl "$@"; }

# part a: order independence, optional task reporting, and strictness
fresh_state kind-kbook kbook alpha
runlab setup a
kc -n ch03-kubectl run api --image=nginx:1.27 --labels=app=api >/dev/null      # created BEFORE the other tasks
runlab solve a
out="$(verify_out a)"
if [[ "$out" == *"All 6 tasks passed"* ]]; then pass "part a: a Pod created early does not change the expected answers"; else flunk "part a: a Pod created early does not change the expected answers"; printf '%s\n' "$out" | tail -8 | sed 's/^/        /'; fi
if [[ "$out" == *"Optional tasks done: 1 of 1"* ]]; then pass "part a: the optional jq/yq task is reported separately"; else flunk "part a: the optional jq/yq task is reported separately"; fi
echo wrong > /tmp/ch03-a1.txt
out="$(verify_out a)"
if [[ "$out" == *"FAIL  Task 1"* && "$out" == *"PASS  Task 2"* ]]; then pass "part a: a wrong answer fails only its own task"; else flunk "part a: a wrong answer fails only its own task"; fi
runlab setup a; runlab solve a
kc -n ch03-kubectl delete pod api >/dev/null
kc -n ch03-kubectl apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: api, labels: {app: api}}
spec:
  containers:
    - {name: api, image: "nginx:1.27"}
    - {name: sneaky, image: "busybox:1.36"}
YAML
out="$(verify_out a)"
if [[ "$out" == *"FAIL  Task 5"* ]]; then pass "part a: an extra container is rejected"; else flunk "part a: an extra container is rejected"; fi

# part b2p: the image must be changed in place
fresh_state kind-kbook kbook alpha
runlab setup b2p; runlab solve b2p
kc -n ch03-b2p delete pod web >/dev/null
kc -n ch03-b2p run web --image=nginx:1.27 --labels=tier=front >/dev/null
kc -n ch03-b2p annotate pod web contact=ops >/dev/null
out="$(verify_out b2p)"
if [[ "$out" == *"FAIL  Task 4"* && "$out" == *"PASS  Task 3"* ]]; then pass "part b2p: recreating the Pod instead of editing it in place is rejected"; else flunk "part b2p: recreating the Pod instead of editing it in place is rejected"; printf '%s\n' "$out" | tail -8 | sed 's/^/        /'; fi

# part b1: reader-created contexts, safety, and restoring the original context
fresh_state kind-kbook kbook alpha
runlab setup b1; runlab solve b1
kc config use-context ch03-a >/dev/null
if in_sb bash tools/run-lab.sh 3 verify b1 >/dev/null 2>&1; then pass "part b1: verify works while sitting on a context the reader created"; else flunk "part b1: verify works while sitting on a context the reader created"; fi
kc config set-context other-ctx --cluster=kind-production --user=kind-production >/dev/null
kc config use-context other-ctx >/dev/null
expect "part b1: a context that is not in LAB_EXTRA_CONTEXTS is still refused" nonzero "requires 'kind-kbook'" -- bash tools/run-lab.sh 3 verify b1
kc config use-context ch03-a >/dev/null
runlab teardown b1
if [[ "$(kubectl config current-context)" == "kind-kbook" && "$(cur_ns)" == "alpha" ]]; then pass "part b1: teardown restores your original context and namespace"; else flunk "part b1: teardown restores your original context and namespace ($(kubectl config current-context) / $(cur_ns))"; fi
if state_has "'ch03-a' not in st['contexts'] and 'ch03-b' not in st['contexts'] and 'ch03-b1-a' not in st['namespaces']"; then pass "part b1: teardown removes the contexts and namespaces it created"; else flunk "part b1: teardown removes the contexts and namespaces it created"; fi
fresh_state kind-kbook "" alpha
kc config set-context ch03-a --cluster=kind-kbook --user=kind-kbook >/dev/null
kc config use-context ch03-a >/dev/null
expect "an extra context on an UNMARKED cluster is refused" nonzero "not marked as a lab cluster" -- bash tools/run-lab.sh 3 verify b1

# part b3: unknown answers are never accepted
fresh_state kind-kbook kbook alpha
runlab setup b3; printf 'no\nno\nyes\nno\n' > /tmp/ch03-b3.txt
out="$(verify_out b3)"
if [[ "$out" == *"PASS  Task 1"* ]]; then pass "part b3: the correct yes/no answers pass"; else flunk "part b3: the correct yes/no answers pass"; fi
printf 'yes\nno\nyes\nno\n' > /tmp/ch03-b3.txt
out="$(verify_out b3)"
if [[ "$out" == *"FAIL  Task 1"* ]]; then pass "part b3: a wrong answer fails"; else flunk "part b3: a wrong answer fails"; fi
rm -f /tmp/ch03-*.txt /tmp/ch03-*.yaml

echo
if ((failures == 0)); then echo "All framework tests passed."; else echo "${failures} framework test(s) failed."; exit 1; fi
