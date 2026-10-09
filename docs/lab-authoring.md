# Lab authoring guide

A lab is a small, disposable, self-checking scenario. Readers should be able to
wreck it and be back at the starting line in under a minute.

## The contract

| Script | Rules |
|---|---|
| `setup.sh` | Idempotent. Starts by tearing down previous state, then builds the exact starting state. Ends only when the lab is ready to use (wait for what must be running). |
| `reset.sh` | Tears down and calls `setup.sh`. Never leaves half a lab behind. |
| `verify.sh` | **Read-only, and CI proves it** (a before/after snapshot of the lab namespace(s) must match). One `check` per task, with ids `1..n` in the order the tasks appear in the chapter text. Prints PASS/FAIL and a hint on FAIL. Exits non-zero if any task fails. With `LAB_ONLY_TASK=<id>` it runs only that check (the step runner uses this). |
| `solve.sh` | Applies the reference solution non-interactively. Used by CI; also handy for readers who are truly stuck. It runs once, right after `setup.sh`, and **need not be idempotent** (running it twice may fail, which is fine). |
| `teardown.sh` | *Optional but expected.* Ends the lab: removes what it created (namespace, answer files, contexts) and restores the reader's kubectl context and namespace. Run with `make teardown CH=n`. Required for any lab that creates contexts or writes files outside the cluster. |
| `solutions.md` | Human-readable solutions with the reasoning. |

`lab.env` defines:

```bash
LAB_NS=ch04-pods    # the namespace the lab owns (Tier 1)
LAB_TIER=1          # 1 = kind, 2 = multi-VM kubeadm
# LAB_CONTEXT=...   # Tier 2: the kubectl context the lab must run against
# LAB_PARTS="a b1"  # optional: split the lab into parts (see below)
# LAB_NS_b1=...     # optional: per-part namespace (used by `make use-namespace` and CI)
# LAB_SNAPSHOT_NS="ns1 ns2"      # optional: every namespace CI must prove verify leaves untouched
# LAB_SNAPSHOT_NS_b1="ns1 ns2"   # ...or per part (this wins over LAB_SNAPSHOT_NS)
# LAB_EXTRA_CONTEXTS="ch03-a"    # contexts the READER creates and may be sitting on (see below)
```

## Rules

1. **Own your namespace.** Tier 1 labs create `LAB_NS` and put everything in it. Reset deletes that namespace. Never leave state in `default` or `kube-system`.
2. **Safety first.** Every script calls `require_lab_cluster` before touching anything. It demands two things: the current context must be **exactly** `kind-${CLUSTER_NAME}` (Tier 2: `$LAB_CONTEXT`), and the cluster must carry the marker ConfigMap `kube-system/kbook-lab-marker` that `make cluster` creates. A context that merely looks like a lab (`kind-production`) is refused. `LAB_ALLOW_ANY_CONTEXT=1` overrides both, deliberately and at the user's own risk.
3. **Cluster-scoped objects need cleanup.** If a lab creates a ClusterRole, PV, StorageClass, CRD, or node label/taint, `setup.sh` must remove the leftovers of a previous run and the chapter text must say so.
4. **No sleeping.** Use `wait_for` with a timeout and a description. Never `sleep 30` and hope.
5. **Pin everything.** Images with explicit tags (no `latest`), tool versions from `versions.env`.
6. **Local state lives in `lab/.state/`** (git-ignored). **Never wipe the whole directory**: it also holds the saved kubectl context (`.state/kubectx`), so remove only your own files (`rm -f .state/code`). Files the reader writes must go to a documented, fixed path (for example `/tmp/chNN-*.txt`); `setup.sh` and `teardown.sh` remove them. Exam-style labs and mock exams use answer folders instead, `/tmp/kbook/<lab>/<question>/`: `setup.sh` calls `lab_course_reset "$COURSE" 2 5 ...` to recreate them empty, `teardown.sh` calls `lab_course_remove "$COURSE"`, and both refuse any path that is not exactly one level below `/tmp/kbook`.
7. **Checks test outcomes, not commands.** Verify the resulting cluster state, so any valid approach (imperative, YAML, `edit`, `patch`) passes.
8. **Checks must be non-vacuous.** CI proves that **every** task fails on its own on the untouched lab and after `reset`, and that `verify.sh` passes after `solve.sh`. If a check passes before the reader does anything, it is a bug. One check per task: a task is either done or not; put every condition the task states into its one check function.
9. **Helpful hints.** A hint points at what to look at, not the answer.
10. **Randomize where copying would cheat.** If a task asks the reader to find a value, generate it at setup time and record it in `lab/.state/`.
11. **No `grep -q` at the end of a pipeline when `pipefail` is set.** `grep -q` exits at the first match, the upstream command can then die of SIGPIPE, and the pipeline intermittently reports failure. Capture the output first (`out="$(cmd)"`), then `grep -q ... <<<"$out"`, or compare with `[[ "$out" == *text* ]]`. This is a real race, not a style point.
12. **Always pass `-n`.** Lab scripts never rely on the reader's default namespace, and `lab_create_ns` does **not** change the kubeconfig. Readers who want `kubectl` to default to the lab namespace opt in with `make use-namespace CH=n`, and `make teardown` restores their settings.
13. **Enforce every constraint the task text states.** If the text says "its only container", the check must count containers; if it says "exactly", check exactly. Conversely, do not let the text promise less than the check demands. State clearly whether a task is an *outcome* contract (these properties must hold) or an *exact object* contract.
14. **Keep helper workloads small.** Background Pods a lab starts for the reader to inspect get small requests and limits, so many labs can coexist on one cluster.
15. **Fast.** Aim for `setup.sh` under 60 seconds on a warm kind cluster.

## Multi-part labs

A chapter can split its lab into independent parts, each with its own scenario,
namespace, checks, and reset. Declare them in `lab.env`:

```bash
LAB_PARTS="a b1 b2"     # the first one is the default
```

Readers pick a part with `PART`: `make lab CH=3 PART=b1`, `make verify CH=3 PART=b1`.
`tools/run-lab.sh` validates the part and exports it to your scripts as `$LAB_PART`.
Typical layout (Chapter 03 is the reference): `setup.sh`, `verify.sh`, `solve.sh`,
`teardown.sh` are thin dispatchers that source `lab/common.sh`, which sources
`lab/parts/<part>.sh`; each part file defines `part_setup`, `part_verify`,
`part_solve`, and `part_teardown`. `reset.sh` just runs `setup.sh`, which always
starts by tearing the part down.

Rules for parts:

- Parts must not depend on each other's state. Each gets its own namespace, named with the part (for example `ch03-b1-a`).
- `make test CH=n` runs the full loop for **every** part; `make test CH=n PART=x` runs one.
- A chapter without `LAB_PARTS` rejects `PART` with a usage error (exit code 2), and an unknown part is also a usage error, so a typo can never look like a passing or failing lab.

## Changing the reader's kubeconfig

Labs that create contexts or change the current context or namespace must undo
it. `tools/lib.sh` provides helpers:

```bash
lab_save_kubectx    "${here}/.state/kubectx"   # in setup.sh; keeps the ORIGINAL on repeat runs
lab_restore_kubectx "${here}/.state/kubectx"   # in teardown.sh (and reset if it rebuilds contexts)
lab_delete_contexts ch03-a ch03-b              # contexts the lab created
```

- Only create contexts whose names start with the chapter prefix (`ch03-`), so cleanup can never touch a reader's own contexts.
- A lab whose point is to have the reader create and switch contexts lists their names in `LAB_EXTRA_CONTEXTS`, so `require_lab_cluster` accepts them as the current context. The **marker check still applies** to whatever cluster they point at, so this can never reach an unmarked cluster. Only list names that start with the chapter prefix.
- Before deleting a context, make sure the reader is not sitting on it (switch to the lab context first), or every later `kubectl` call fails.
- `lab_create_ns` does **not** touch the kubeconfig. Only `make use-namespace` (tools/use-namespace.sh) changes the default namespace, and it saves the original first so `make teardown` can restore it.
- Save with `lab_save_kubectx` at most once per lab run; it keeps the original on repeat calls, so repeated `use-namespace` calls never overwrite what the reader had.
- `tools/test-lib.sh` unit-tests these helpers against a throwaway kubeconfig; it needs `kubectl` but no cluster (`make test-lib`).

## Two lab styles

Chapter labs are **step by step** (KodeKloud style, below): one task at a time,
`check` per task, KodeKloud-style specification lists. They are for learning.

The last lab of a Part (Chapter 03's `final` part) and every mock exam are
**exam style** (killer.sh): all questions at once, answered in any order,
scored together by `verify.sh`. They are for rehearsing the exam. In the text,
questions are `Question N | Title` headings, each followed by a plain
`Task weight: N%` line, a `Use context: kubectl config use-context ...` line,
and terse text that names every Namespace and answer file in full. In
`verify.sh`, use `check_weighted <id> <weight> <description> <hint> <command>`
instead of `check`; weights must add up to 100 (`finish_checks` refuses
otherwise) and it prints the weighted score. A question still counts only when
all of it is right. Never mix `check` and `check_weighted` in one `verify.sh`.

## Mock exams

A mock exam lives in `mock-exams/<name>/` with the same layout as a chapter
(`<name>.md` holds the questions as `## Question N | Title` headings, `lab/`
the scripts, `manifests/` the seeds), so every tool works on it by name:
`make mock EXAM=<name>` runs `setup.sh`, `make mock-score` runs `verify.sh`,
`make mock-test` runs the CI loop. In addition to the chapter rules:

- `lab.env` sets `EXAM_MINUTES` and `EXAM_PASS_PERCENT`; `verify.sh` passes the
  pass mark to `finish_checks` as `KBOOK_PASS_PERCENT` and calls
  `report_elapsed` for the time used.
- Use several Namespaces and at least two contexts of your own (prefixed with
  the exam name, listed in `LAB_EXTRA_CONTEXTS`), so readers practise switching
  context per question. List every Namespace in `LAB_SNAPSHOT_NS`.
- Cover only chapters that exist. Aim to be harder and more hurried than the
  real exam, as killer.sh is, and randomize every value a reader must find.

## Step by step (KodeKloud style)

Readers work through a lab one task at a time, as in KodeKloud's labs:
`make lab` shows task 1, `make check` checks only the current task and, when
it is correct, shows the next one; otherwise it prints the hint. `make
question` repeats the current task, `make skip` moves on, `make reset` returns
to task 1, and `make verify` still checks everything at once.

`tools/step.sh` reads the tasks from the chapter text, so there is one source
for them:

- In the `## Hands-on lab` section, every `### Task <id>: <title>` heading is
  a task; for a lab with parts, every `#### Task <id>: <title>` heading under
  `### Part <part>: ...`. The block under the heading, up to the next heading,
  is what the reader sees. Put lab-wide notes **above** the first task, never
  after the last one, or the runner shows them as part of that task.
- The Nth task heading is checked by `check N` in `verify.sh`. The ids in the
  headings (`A1`, `B1.3`) are only labels; order is what counts.
- Progress lives in `lab/.state/step` (or `step-<part>`); `make teardown`
  clears it.

CI walks the runner through every task after `solve.sh` (each `make check`
must pass, in order, and the lab must end complete) and proves there is no
check beyond the last task, so text and checks always line up one to one.

## Skeletons

`setup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${here}/../../../tools/lib.sh"
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
lab_create_ns "$LAB_NS"
# ... seed resources, then wait for readiness ...
info "Lab ready."
```

`verify.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${here}/../../../tools/lib.sh"
source "${here}/lab.env"
require_lab_cluster

t1() { [[ "$(kubectl -n "$LAB_NS" get pod web -o jsonpath='{.status.phase}')" == "Running" ]]; }
check 1 "pod web is running" "look at 'kubectl get pods'" t1

finish_checks
```

## What CI proves for every lab

`make test CH=n` (all parts, or `PART=x`) and `make mock-test EXAM=name` fail unless all of these hold:

1. `verify.sh` fails on the untouched lab, and after `reset`; so does every task on its own (`LAB_ONLY_TASK=<id>`).
2. `setup.sh` is idempotent (run twice in a row).
3. `verify.sh` is read-only: a normalized snapshot of the lab namespace(s) is identical before and after every verify run.
4. `verify.sh` passes after `solve.sh`. The tasks in the text and the checks match one to one (no check beyond the last task), and for step-by-step labs `make check` passes every task in order, ending with the lab complete.
5. Unrelated cluster state survives: a sentinel namespace, ConfigMap, and ClusterRole created before the run must still exist with the same UIDs after every part.

`make test-harness` tests these guarantees themselves against a fake `kubectl` (it deliberately feeds the loop broken labs and unsafe clusters and checks that they are caught). Run it whenever `tools/` changes. `make test-lib` covers the kubeconfig helpers and `make test-render` the question validator.

Stretch tasks: use `check_optional` instead of `check`. A done task prints PASS, an undone one prints TODO with the hint, and neither can fail the lab; `finish_checks` reports how many optional tasks are done. CI still proves the reference solution completes them.

Order independence: a check must not depend on the order a reader does tasks in. If a task creates an object that another task's answer would otherwise include (a new Pod matching a selector, say), compute the expected answer from the seeded objects only. Chapter 03 part a shows how.

Debugging a check: `LAB_DEBUG=1 make verify CH=n` prints a shell trace, including any `kubectl` error, for each failing check.

## Tier 2 labs

Tier 2 labs run against the multi-VM kubeadm environment in `envs/`. They set
`LAB_TIER=2` and `LAB_CONTEXT`. Reset restores VM snapshots instead of deleting
namespaces; the snapshot name is recorded in `lab.env` as `LAB_SNAPSHOT`.
Tier 2 environment work is Phase 2 in `ROADMAP.md`.
