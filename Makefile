# Usage: make help
include versions.env
export

CH ?=
PART ?=
SHELL := /usr/bin/env bash

.PHONY: help cluster cluster-recreate cluster-delete lab use-namespace reset verify solve teardown test test-lib test-harness test-render test-shell test-examples test-tier1 questions questions-check lint

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*## ' Makefile | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'
	@echo; echo "Chapter targets need CH=<number>, e.g. make lab CH=4."; echo "Labs with parts also take PART=<part>, e.g. make lab CH=3 PART=b1."

cluster: ## Create the Tier 1 kind cluster if needed, check its version, and mark it as a lab cluster
	@bash tools/cluster.sh

cluster-recreate: ## Delete and rebuild the Tier 1 cluster (use after changing versions.env)
	@kind delete cluster --name "$(CLUSTER_NAME)"
	@bash tools/cluster.sh

cluster-delete: ## Delete the Tier 1 kind cluster
	kind delete cluster --name "$(CLUSTER_NAME)"

lab: ## Set up the lab for CH (also resets it if it already exists)
	@bash tools/run-lab.sh "$(CH)" setup "$(PART)"

use-namespace: ## Opt in: make kubectl default to CH's lab namespace (make teardown restores it)
	@bash tools/run-lab.sh "$(CH)" use-namespace "$(PART)"

reset: ## Reset the lab for CH to its starting state
	@bash tools/run-lab.sh "$(CH)" reset "$(PART)"

verify: ## Check your work for CH
	@bash tools/run-lab.sh "$(CH)" verify "$(PART)"

solve: ## Apply the reference solution for CH (spoilers!)
	@bash tools/run-lab.sh "$(CH)" solve "$(PART)"

teardown: ## End the lab for CH: remove what it created and restore your kubectl context
	@bash tools/run-lab.sh "$(CH)" teardown "$(PART)"

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

test-lib: ## Unit-test the shared shell helpers (needs kubectl; no cluster)
	@bash tools/test-lib.sh

test-tier1: ## Run the loop for every Tier 1 chapter (fails if there are none)
	@set -e; list="$$(bash tools/list-chapters.sh 1)"; \
	  if [ -z "$$list" ]; then echo "error: no Tier 1 labs found" >&2; exit 1; fi; \
	  for n in $$list; do bash tools/test-lab.sh $$n; done

questions: ## Render questions.yaml into every chapter file
	@python3 tools/render-questions.py

questions-check: ## Fail if any chapter file is out of date with its questions.yaml
	@python3 tools/render-questions.py --check

lint: ## shellcheck, yamllint, markdownlint
	@shellcheck -x tools/*.sh envs/shell/*.sh chapters/*/lab/*.sh chapters/*/lab/parts/*.sh chapters/*/testdata/*.sh
	@yamllint -c .yamllint .
	@markdownlint-cli2 "**/*.md" "#node_modules"
