# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A hands-on textbook for the five Kubestronaut certifications (KCNA, KCSA, CKAD, CKA, CKS). Each chapter is Markdown text plus a self-checking, resettable lab that runs against a kind cluster. `ROADMAP.md` holds the full chapter plan, lab tiers, and the chapter definition of done; `docs/` holds the author rules (`style-guide.md`, `chapter-template.md`, `lab-authoring.md`, `coverage-matrix.md`, and per-chapter plans in `docs/plans/`). Read `docs/lab-authoring.md` before touching any lab script: its rules are enforced by CI.

All tooling is bash + `make` (the Makefile sets `SHELL := /usr/bin/env bash`), so run it from Linux/WSL, not PowerShell.

## Commands

Chapter targets take `CH=<number>`; multi-part labs also take `PART=<part>` (the first part in `LAB_PARTS` is the default).

```bash
make cluster                 # create the kind cluster "kbook" and its safety marker ConfigMap
make lab|verify|reset|solve|teardown CH=4 [PART=b1]
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

CI (`.github/workflows/labs.yml`) runs lint, questions-check, test-render, test-harness, test-shell, test-examples, then a kind cluster with test-lib and test-tier1. It also runs weekly to catch upstream drift.

## Architecture

- **`versions.env`** is the single source of truth for the Kubernetes version, kind node image, cluster name, and tool pins. The Makefile `include`s and exports it; CI reads it too. Never hard-code versions elsewhere.
- **`tools/run-lab.sh`** is the dispatcher behind every chapter target: it resolves the chapter dir (`lab-path.sh`), validates `PART` against `LAB_PARTS` (bad/unexpected part = exit 2), exports `LAB_PART`, and execs `chapters/NN-*/lab/<action>.sh`. `use-namespace` is generic (`tools/use-namespace.sh`), not per-lab.
- **`tools/lib.sh`** is sourced by every lab script and provides `require_lab_cluster`, `lab_create_ns`/`lab_teardown_ns`, `wait_for`, `check`/`check_optional`/`finish_checks`, and `lab_save_kubectx`/`lab_restore_kubectx`/`lab_delete_contexts`. `require_lab_cluster` refuses to run unless the context is exactly `kind-${CLUSTER_NAME}` (or `LAB_CONTEXT`/`LAB_EXTRA_CONTEXTS`) **and** the cluster has `kube-system/kbook-lab-marker`.
- **`tools/test-lab.sh`** proves, per part: verify fails on the untouched lab and after reset (non-vacuous checks), setup is idempotent, verify is read-only (normalized namespace snapshot via `snapshot-state.sh`/`snapshot-normalize.py` must match before/after), verify passes after solve, and sentinel namespace/ConfigMap/ClusterRole survive with the same UIDs. Run `make test-harness` whenever `tools/` changes.
- **Questions** live in each chapter's `questions.yaml` (types `mcq` and `task`, exam tags limited to KCNA/KCSA/CKAD/CKA/CKS) and are rendered between `<!-- QUESTIONS:START -->` / `<!-- QUESTIONS:END -->` in the chapter file. Edit the YAML, then `make questions`; never hand-edit the rendered block.

### Chapter layout

`chapters/NN-slug/NN-slug.md` (never `README.md`), `questions.yaml`, optional `manifests/`, and `lab/` with `lab.env`, `setup.sh`, `reset.sh`, `verify.sh`, `solve.sh`, optional `teardown.sh`, `solutions.md`. Copy `chapters/04-pods/` as the single-part template; `chapters/03-kubectl-fluency/` is the multi-part reference (thin dispatchers → `lab/common.sh` → `lab/parts/<part>.sh` defining `part_setup`/`part_verify`/`part_solve`/`part_teardown`). Concept-only chapters (e.g. 01) have no `lab/` and are skipped by `test-tier1`.

### Lab rules that are easy to break

- Each lab owns `LAB_NS` (per-part namespaces include the part name); never put state in `default`/`kube-system`. Always pass `-n`; `lab_create_ns` never changes the kubeconfig.
- Local state goes in `lab/.state/` (git-ignored) but **never wipe the whole directory**: it holds `.state/kubectx`. Reader answer files go to fixed paths like `/tmp/chNN-*.txt`, removed by setup and teardown.
- No `sleep`; use `wait_for`. Pin image tags (no `latest`).
- Checks test outcomes, not commands, must not depend on task order, and must enforce every constraint the task text states (and no more).
- With `pipefail`, never end a pipeline in `grep -q`: capture output first, then `grep -q ... <<<"$out"`.
- Contexts a lab creates must start with the chapter prefix (`ch03-`).

## Writing conventions (from `docs/style-guide.md` / `docs/chapter-template.md`)

- Second person, present tense; no "simply/just/obviously". Explain why before how.
- `bash` fences for commands (no prompts), separate `text`/`yaml` fences for output. Show imperative `kubectl` first, then the YAML via `--dry-run=client -o yaml`. Commands must have been run on the pinned version.
- Official API kind capitalization (Pod, Deployment); "control plane node", never "master". Mermaid diagrams only, under ~15 nodes, with a nearby text description.
- Exam callouts use exactly `> **Exam tip:** ...` and must never imply real exam content. Questions are original, 10–15 per chapter, every answer explained.
- Labs: 3–6 tasks, formatted `### Task N: Title (⏱ N min, ★★☆)` with a *Success looks like:* line; state the goal, not the command.
- Markdownlint allows only `<details>`, `<summary>`, `<br>` HTML; line length is not enforced.
