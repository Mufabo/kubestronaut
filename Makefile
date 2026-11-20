# Usage: make help
include versions.env
export

CH ?=
PART ?=
EXAM ?=
PROFILE ?=
PROFILES ?=
SHELL := /usr/bin/env bash

.PHONY: help cluster cluster-fresh cluster-status cluster-recreate cluster-delete cluster-pause cluster-resume netlab netlab-rebuild shell netlab-down netlab-status test-tier0 test-tier2-env lab question check skip use-namespace reset verify solve teardown test test-lib test-harness test-render test-shell test-examples test-tier1 mock mock-score mock-reset mock-solve mock-teardown mock-test test-mocks quiz quiz-reset test-quiz epub questions questions-check lint

help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' Makefile | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'
	@echo; echo "Chapter targets need CH=<number>, e.g. make lab CH=4."; echo "Labs with parts also take PART=<part>, e.g. make lab CH=3 PART=b1."
	@echo "Mock exam targets need EXAM=<name>, e.g. make mock EXAM=part1 (see mock-exams/)."

cluster: ## Make sure the Tier 1 kind cluster runs PROFILE (default calico); builds or rebuilds it if needed
	@bash tools/cluster.sh up "$(or $(PROFILE),calico)"

cluster-fresh: ## Delete and rebuild the Tier 1 cluster with PROFILE (default calico)
	@bash tools/cluster.sh fresh "$(or $(PROFILE),calico)"

cluster-recreate: cluster-fresh ## Same as cluster-fresh (use after changing versions.env)

cluster-delete: ## Delete the Tier 1 kind cluster
	@bash tools/cluster.sh down

cluster-status: ## Show the Tier 1 cluster's profile and nodes
	@bash tools/cluster.sh status

cluster-pause: ## Stop the Tier 1 kind cluster's containers (frees RAM for the Tier 2 VMs)
	@ids="$$(docker ps -q --filter label=io.x-k8s.kind.cluster=$(CLUSTER_NAME))"; if [ -z "$$ids" ]; then echo "kind cluster $(CLUSTER_NAME) is not running"; else docker stop $$ids >/dev/null && echo "kind cluster $(CLUSTER_NAME) paused; make cluster-resume starts it again"; fi

cluster-resume: ## Start the paused Tier 1 kind cluster again and wait for its nodes
	@ids="$$(docker ps -aq --filter label=io.x-k8s.kind.cluster=$(CLUSTER_NAME))"; [ -n "$$ids" ] || { echo "no kind cluster $(CLUSTER_NAME); run: make cluster" >&2; exit 1; }; docker start $$ids >/dev/null; for i in $$(seq 1 90); do kubectl --context kind-$(CLUSTER_NAME) get nodes >/dev/null 2>&1 && break; sleep 2; done; kubectl --context kind-$(CLUSTER_NAME) wait --for=condition=Ready node --all --timeout=180s

netlab: ## Build the Part V lab image (once) and start the netlab container
	@bash tools/netlab.sh up

netlab-rebuild: ## Rebuild the netlab image from envs/netlab (after changing it)
	@FORCE=1 bash tools/netlab.sh build

shell: ## Open a shell inside the netlab container (Part V labs)
	@bash tools/netlab.sh shell

netlab-down: ## Remove the netlab container
	@bash tools/netlab.sh down

netlab-status: ## Show whether the netlab image and container exist
	@bash tools/netlab.sh status

test-tier2-env: ## Smoke-test the Tier 2 VMs (run inside cp1, on any snapshot)
	@bash tools/test-tier2-env.sh

lab: ## Set up the lab for CH (also resets it) and show its first task
	@bash tools/run-lab.sh "$(CH)" setup "$(PART)"
	@bash tools/step.sh "$(CH)" start "$(PART)"

question: ## Show the current task of CH's lab again
	@bash tools/step.sh "$(CH)" question "$(PART)"

check: ## Check the current task of CH's lab; if it is correct, show the next one
	@bash tools/step.sh "$(CH)" check "$(PART)"

skip: ## Move on to the next task of CH's lab without checking
	@bash tools/step.sh "$(CH)" skip "$(PART)"

use-namespace: ## Opt in: make kubectl default to CH's lab namespace (make teardown restores it)
	@bash tools/run-lab.sh "$(CH)" use-namespace "$(PART)"

reset: ## Reset the lab for CH to its starting state and go back to task 1
	@bash tools/run-lab.sh "$(CH)" reset "$(PART)"
	@bash tools/step.sh "$(CH)" start "$(PART)"

verify: ## Check every task of CH at once
	@bash tools/run-lab.sh "$(CH)" verify "$(PART)"

solve: ## Apply the reference solution for CH (spoilers!)
	@bash tools/run-lab.sh "$(CH)" solve "$(PART)"

teardown: ## End the lab for CH: remove what it created and restore your kubectl context
	@bash tools/run-lab.sh "$(CH)" teardown "$(PART)"
	@bash tools/step.sh "$(CH)" clear "$(PART)"

test: ## Run the full setup/verify/solve/reset loop for CH, all parts (or PART=x)
	@bash tools/test-lab.sh "$(CH)" "$(PART)"

test-harness: ## Test the lab framework itself against a fake kubectl (no cluster needed)
	@bash tools/test-harness.sh

test-shell: ## Test envs/shell (helpers, vimrc, install/uninstall) with a stub kubectl
	@bash tools/test-shell.sh

test-examples: ## Check every jq/yq example in Chapter 03 against real jq and yq (needs both)
	@bash chapters/03-kubectl-fluency/testdata/test-examples.sh

test-render: ## Unit-test the question renderer's validation
	@python3 tools/test_render_questions.py

test-quiz: ## Unit-test the multiple-choice quiz runner and validate every quiz bank
	@python3 tools/test_quiz.py

test-lib: ## Unit-test the shared shell helpers (needs kubectl; no cluster)
	@bash tools/test-lib.sh

test-tier0: ## Run the loop for every Tier 0 (netlab) chapter of Part V
	@set -e; list="$$(bash tools/list-chapters.sh 0)"; \
	  if [ -z "$$list" ]; then echo "error: no Tier 0 labs found" >&2; exit 1; fi; \
	  for n in $$list; do bash tools/test-lab.sh $$n; done

test-tier1: ## Run the loop for every Tier 1 chapter, or only those on PROFILES (e.g. PROFILES="nocni cilium")
	@set -e; list="$$(bash tools/list-chapters.sh 1 $(PROFILES))"; \
	  if [ -z "$$list" ]; then echo "error: no Tier 1 labs found" >&2; exit 1; fi; \
	  for n in $$list; do bash tools/test-lab.sh $$n; done

mock: ## Start mock exam EXAM; the clock starts when it is ready
	@bash tools/run-lab.sh "$(EXAM)" setup
	@bash tools/step.sh "$(EXAM)" start

mock-score: ## Score mock exam EXAM (as often as you like)
	@bash tools/run-lab.sh "$(EXAM)" verify

mock-reset: ## Start mock exam EXAM over from scratch
	@bash tools/run-lab.sh "$(EXAM)" reset

mock-solve: ## Apply the reference solution for mock exam EXAM (spoilers!)
	@bash tools/run-lab.sh "$(EXAM)" solve

mock-teardown: ## Remove mock exam EXAM and restore your kubectl context
	@bash tools/run-lab.sh "$(EXAM)" teardown

mock-test: ## Run the full CI loop for mock exam EXAM
	@bash tools/test-lab.sh "$(EXAM)"

test-mocks: ## Run the CI loop for every Tier 1 mock exam, or only those on PROFILES (Tier 2 mocks run by hand on cp1)
	@set -e; for name in $$(bash tools/list-chapters.sh --mocks 2); do \
	  echo "=== $$name: Tier 2, skipped (run make mock-test EXAM=$$name on cp1) ==="; done; \
	  for name in $$(bash tools/list-chapters.sh --mocks 1 $(PROFILES)); do bash tools/test-lab.sh "$$name"; done

quiz: ## Take (or resume) the timed multiple-choice exam EXAM, e.g. EXAM=kcna
	@python3 tools/quiz.py "$(EXAM)"

quiz-reset: ## Throw away the current attempt of quiz EXAM
	@python3 tools/quiz.py "$(EXAM)" --reset

epub: ## Build the book as an EPUB in dist/ (needs pandoc, and npx or mmdc for the diagrams)
	@bash tools/build-epub.sh

questions: ## Render questions.yaml into every chapter file and question-only mock exam
	@python3 tools/render-questions.py

questions-check: ## Fail if any chapter file is out of date with its questions.yaml
	@python3 tools/render-questions.py --check

lint: ## shellcheck, yamllint, markdownlint
	@shellcheck -x tools/*.sh envs/shell/*.sh chapters/*/lab/*.sh chapters/*/lab/parts/*.sh chapters/*/testdata/*.sh mock-exams/*/lab/*.sh envs/vagrant/*.sh envs/kind/profiles/*/*.sh
	@shellcheck -s bash envs/netlab/rootfs/bin/on envs/netlab/rootfs/bin/netmap envs/netlab/rootfs/bin/topo envs/netlab/rootfs/topo.sh envs/netlab/rootfs/bashrc
	@python3 -c "import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]" envs/netlab/rootfs/bin/labhttp
	@yamllint -c .yamllint .
	@markdownlint-cli2 "**/*.md" "#node_modules"
