# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A hands-on textbook for the five Kubestronaut certifications (KCNA, KCSA, CKAD, CKA, CKS). Each chapter is Markdown text plus a self-checking, resettable lab that runs against a kind cluster. Chapter labs run step by step like KodeKloud's: `make lab` shows task 1, `make check` checks only the current task and moves on when it is correct. Each Part of the book ends with a mock exam (`mock-exams/`, e.g. `part1` for Chapters 02 to 06), and those mocks, plus a few timed warm-ups inside chapters (Chapter 03 `final`), are exam style like killer.sh: weighted `Question N | Title` items with a `Use context:` line, answer files under `/tmp/kbook/<lab>/<question>/`, all scored at once. Either way, a task is all-or-nothing: one check per task, no partial credit. `ROADMAP.md` holds the full chapter plan, lab tiers, and the chapter definition of done; `docs/` holds the author rules (`style-guide.md`, `chapter-template.md`, `lab-authoring.md`, `coverage-matrix.md`, and per-chapter plans in `docs/plans/`). Read `docs/lab-authoring.md` before touching any lab script: its rules are enforced by CI.

All tooling is bash + `make` (the Makefile sets `SHELL := /usr/bin/env bash`), so run it from Linux/WSL, not PowerShell.

## Commands

Chapter targets take `CH=<number>`; multi-part labs also take `PART=<part>` (the first part in `LAB_PARTS` is the default).

```bash
make cluster                 # create the kind cluster "kbook" and its safety marker ConfigMap
make lab|verify|reset|solve|teardown CH=4 [PART=b1]
make check|question|skip CH=4 [PART=b1]   # step-by-step runner (tools/step.sh)
make mock|mock-score|mock-reset|mock-solve|mock-teardown EXAM=part1
make mock-test EXAM=part1    # full CI loop for one mock exam; make test-mocks runs every Tier 1 mock
make test CH=3 [PART=b1]     # full CI loop for one chapter (needs the cluster)
make test-tier1              # loop over every Tier 1 chapter
make lint                    # shellcheck + yamllint + markdownlint-cli2
make questions               # render questions.yaml into chapter files
make questions-check         # fail if a chapter file is stale vs. its questions.yaml
make test-harness            # tests the lab framework against tools/testdata/fake-kubectl.py (no cluster)
make test-render             # unit tests for tools/render-questions.py
make test-lib                # kubeconfig helper tests (needs kubectl, no cluster)
make test-shell              # envs/shell helpers/vimrc/install
make test-examples           # every jq/yq example in Chapter 03 against pinned jq/yq
LAB_DEBUG=1 make verify CH=4 # shell trace for failing checks
```

Running one thing at a time:

```bash
LAB_ONLY_TASK=3 make verify CH=4   # run only check 3 (no match exits 2)
make check CH=4                    # step-by-step labs: the current task only
make test CH=3 PART=b1             # one part of a multi-part lab
make mock-test EXAM=part1          # one mock exam
python3 tools/test_render_questions.py   # one renderer test file (make test-render runs it)
bash tools/test-lib.sh             # kubeconfig helpers (needs kubectl, no cluster)
bash tools/test-shell.sh           # envs/shell (needs no cluster)
```

Tier 2 labs (Chapters 18, 19, 20, 27) and `mock-exams/part3` run on the VMs, never in CI and never in `test-tier1`/`test-mocks`. Test one by hand: `make cluster-pause` in WSL (frees RAM), restore the lab's `LAB_SNAPSHOT` from the host, then run the loop on `cp1`. `test-lab.sh` checks the snapshot and skips the reset phase, so restore again before every run.

```powershell
.\envs\vagrant\kbook-vm.ps1 restore cluster-prev                          # host; the lab's LAB_SNAPSHOT
cd envs\vagrant; vagrant ssh cp1 -c "cd /kbook && make test CH=19"        # or: make mock-test EXAM=part3
```

No cluster needed: `make lint`, `make questions-check`, `make test-render`, `make test-harness`, `make test-shell`, `make test-lib`, `make test-examples`. Local tools for these: bash, make, shellcheck, yamllint, `markdownlint-cli2` at the version pinned in `versions.env`, pinned `jq` and `yq`, Python 3 with `tools/requirements.txt` (PyYAML), and vim. Labs and `make test*` on a cluster also need docker, kind, and kubectl.

CI (`.github/workflows/labs.yml`) installs the same pinned tools, runs lint, questions-check, test-render, test-harness, test-shell, test-examples, then creates a kind cluster and runs test-lib, test-tier1, and test-mocks. It also runs weekly to catch upstream drift.

## Architecture

- **`versions.env`** is the single source of truth for the Kubernetes version, kind node image, cluster name, and tool pins. The Makefile `include`s and exports it; CI reads it too. Never hard-code versions elsewhere.
- **`tools/run-lab.sh`** is the dispatcher behind every chapter and mock target: it resolves the lab dir (`lab-path.sh`: a number means `chapters/NN-*`, a name means `mock-exams/<name>`), validates `PART` against `LAB_PARTS` (bad/unexpected part = exit 2), exports `LAB_PART`, and execs `<lab dir>/lab/<action>.sh`. `use-namespace` is generic (`tools/use-namespace.sh`), not per-lab.
- **`tools/lib.sh`** is sourced by every lab script and provides `require_lab_cluster`, `lab_create_ns`/`lab_teardown_ns`, `wait_for`, `check`/`check_optional`/`finish_checks` (with `LAB_ONLY_TASK=<id>`, only that check runs; no match exits 2), `check_weighted <id> <weight> ...` for exam-style labs (weights must sum to 100; `KBOOK_PASS_PERCENT` sets a mock's pass mark; never mixed with `check`), `report_elapsed`, `lab_course_reset`/`lab_course_remove` (answer folders, refused outside `/tmp/kbook/<name>`), and `lab_save_kubectx`/`lab_restore_kubectx`/`lab_delete_contexts`. `require_lab_cluster` refuses to run unless the context is exactly `kind-${CLUSTER_NAME}` (or `LAB_CONTEXT`/`LAB_EXTRA_CONTEXTS`) **and** the cluster has `kube-system/kbook-lab-marker`.
- **`tools/test-lab.sh`** proves, per part: verify fails on the untouched lab and after reset (non-vacuous checks), setup is idempotent, verify is read-only (normalized namespace snapshot via `snapshot-state.sh`/`snapshot-normalize.py` must match before/after), every task fails on its own (`LAB_ONLY_TASK`) on the untouched lab and after reset, verify passes after solve, text tasks and checks match one to one, step-by-step labs pass `make check` for every task in order, and sentinel namespace/ConfigMap/ClusterRole survive with the same UIDs. Run `make test-harness` whenever `tools/` changes.
- **`tools/step.sh`** is the KodeKloud-style runner. It reads tasks from the chapter text itself: `### Task <id>: ...` headings in `## Hands-on lab` (or `#### Task` under `### Part <part>: ...` for multi-part labs). The Nth heading is `check N` in `verify.sh`; heading ids like `A1` are labels only. Progress lives in `lab/.state/step[-<part>]`. If the headings are `Question N | ...` instead, the lab is exam style: `make lab` prints a banner and `make check` refuses. Mock exams (`mock-exams/<name>/<name>.md`, `## Question` headings) are always exam style.
- **Tier 2 (`envs/vagrant`)** is three VirtualBox VMs (`cp1`, `node1`, `node2`) built with kubeadm by a host driver (`kbook-vm.ps1` on Windows, `kbook-vm.sh` elsewhere: `build`, `restore <snapshot>`, `ssh`). Snapshots: `prereqs` (tools, no cluster), `cluster` (K8S_VERSION), `cluster-prev` (K8S_PREV_VERSION). Readers and Tier 2 labs run on `cp1` from `/kbook` with context `kbook-vm`; `require_snapshot` checks `/etc/kbook/snapshot`, and `make reset` on a Tier 2 lab only prints the host restore command. CI cannot run it: verify with `make test-tier2-env` on `cp1`. `make cluster-pause`/`cluster-resume` free the RAM the kind cluster holds.
- **Questions** live in each chapter's `questions.yaml` (types `mcq` and `task`, exam tags limited to KCNA/KCSA/CKAD/CKA/CKS). `tools/render-questions.py` renders them between `<!-- QUESTIONS:START -->` / `<!-- QUESTIONS:END -->` in the chapter file. Edit the YAML, then `make questions`; never hand-edit the rendered block. `make questions-check` fails when a chapter file is stale.
- **Step runner and checks stay in one-to-one order.** `tools/step.sh` builds its task list from the `### Task N` headings in the chapter text, and `check N` in `verify.sh` must be the same task. Adding, removing, or reordering a task means changing both.
- **Snapshots ignore CNI noise.** The read-only check compares a normalized namespace snapshot (`snapshot-state.sh`, `snapshot-normalize.py`). The normalizer drops the Calico `cni.projectcalico.org/` annotations, so a CNI change does not look like a lab change.
- **Harness sandbox.** `tools/test-harness.sh` copies the repo into a sandbox and runs the lab framework against `tools/testdata/fake-kubectl.py`, so the loop's guarantees are tested without a cluster. Its copy must not carry a reader's `lab/.state/` (it is deleted from the copy).

### Chapter layout

`chapters/NN-slug/NN-slug.md` (never `README.md`), `questions.yaml`, optional `manifests/`, and `lab/` with `lab.env`, `setup.sh`, `reset.sh`, `verify.sh`, `solve.sh`, optional `teardown.sh`, `solutions.md`. Copy `chapters/04-pods/` as the single-part template; `chapters/03-kubectl-fluency/` is the multi-part reference (thin dispatchers → `lab/common.sh` → `lab/parts/<part>.sh` defining `part_setup`/`part_verify`/`part_solve`/`part_teardown`). Concept-only chapters (e.g. 01) have no `lab/` and are skipped by `test-tier1`. Tier 2 labs (`LAB_TIER=2`, `LAB_SNAPSHOT`, `LAB_CONTEXT=kbook-vm`, `LAB_CLUSTER_NAME=kbook-vm` in `lab.env`) have no `reset.sh`; their `setup.sh` calls `require_snapshot` and refuses a cluster that has already been changed, and helpers they share live in `lab/common.sh` (Chapter 20 and 27 are the references; Chapter 18 starts from `prereqs`, with no cluster at all).

Captured command output for Tier 2 chapters comes from scratch scripts in `envs/vagrant/.state/` (git-ignored, mounted on `cp1` at `/kbook/envs/vagrant/.state/`), run with `vagrant ssh cp1 -c "bash /kbook/envs/vagrant/.state/<script>.sh"`. From PowerShell, put multi-command or quoted work in such a script rather than inline: PowerShell 5.1 rejects `&&` and mangles nested quotes.

A mock exam (`mock-exams/<name>/`) has the same layout, with the questions in `<name>.md`. Its `lab.env` adds `EXAM_MINUTES` and `EXAM_PASS_PERCENT`, lists all its Namespaces in `LAB_SNAPSHOT_NS`, and lists its own contexts in `LAB_EXTRA_CONTEXTS`; `mock-exams/part1` is the reference. `mock-exams/part3` runs on the Tier 2 VMs (snapshot `cluster-prev`) and is tested by hand on `cp1`. After `solve.sh`, the test loop requires every question to pass (`KBOOK_REQUIRE_ALL=1`), not only the pass mark.

### Lab rules that are easy to break

- Each lab owns `LAB_NS` (per-part namespaces include the part name); never put state in `default`/`kube-system`. Always pass `-n`; `lab_create_ns` never changes the kubeconfig.
- Local state goes in `lab/.state/` (git-ignored) but **never wipe the whole directory**: it holds `.state/kubectx`. Reader answer files go to fixed paths like `/tmp/chNN-*.txt`, removed by setup and teardown.
- No `sleep`; use `wait_for`. Pin image tags (no `latest`).
- Checks test outcomes, not commands, must not depend on task order, and must enforce every constraint the task text states (and no more).
- With `pipefail`, never end a pipeline in `grep -q`: capture output first, then `grep -q ... <<<"$out"`.
- Contexts a lab creates must start with the chapter prefix (`ch03-`).

## Writing conventions

The full rules are in `docs/style-guide.md` and `docs/chapter-template.md`; read them before writing a chapter. The ones easiest to break:

- Commands in `bash` fences with no prompts; output in separate `text`/`yaml` fences. Commands must have been run on the pinned version.
- Exam callouts use exactly `> **Exam tip:** ...` and must never imply real exam content. Questions are original, 10–15 per chapter, and every answer is explained.
- Labs are 3–6 tasks as `### Task N: Title`. Each task states the goal and a spec list of exactly what the check enforces. Lab-wide notes go above the first task. Exam-style labs use `Question N | Title`, a plain `Task weight: N%` line (no emphasis, for MD036), and a `Use context:` line.
- Markdownlint allows only `<details>`, `<summary>`, and `<br>` HTML; line length is not enforced.
