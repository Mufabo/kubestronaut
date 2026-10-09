# Plan: Chapter 03, Lab setup and `kubectl` fluency

Status: **implemented** (chapter, six-part lab, shell setup, jq/yq tests, cheat sheet). Not yet run on a real cluster. All open questions are resolved (section 11). Chapter file will be
`chapters/03-kubectl-fluency/03-kubectl-fluency.md`.

## 1. Purpose and position in the book

- **Exams served:** KCNA, CKAD, CKA (and every later hands-on chapter and CKS depend on it).
- **Lab tier:** 1 (kind).
- **Estimated learner time:** ~90 min reading, ~60 min lab.
- **Prerequisites:** Chapters 01 and 02. Chapter 02 already teaches the minimum `kubectl` primer (`get`, `describe`, `-n`, `-A`, `-l`, `explain`, contexts) and how kubeconfig is structured. This chapter goes deeper and **must not repeat** that material beyond a one-paragraph recap.
- **Why it matters:** the CKAD, CKA, and CKS exams are timed and performance-based. Command fluency and a fast shell are worth points directly.

## 2. Decisions already made

| Decision | Choice |
|---|---|
| Lab structure | **All three:** a shared seeded set of Pods, fresh mini-scenarios with their own reset, and guided drills plus a timed final task |
| Shell and exam setup (aliases, completion, vim) | **Full treatment in this chapter** (Chapter 37 then covers strategy and mock-exam technique, not setup) |
| `jq` and `yq` | **Covered** in the chapter, alongside built-in `kubectl` output tools |
| `tmux` | **A short optional box** in the chapter, no separate config file |
| Windows | **WSL2 only**; no native PowerShell support |
| Scope of Part A | **Pods only** (no Deployments yet); complexity kept as low as sensible |
| Part b2 | **Two variants:** `b2` (ConfigMap, Secret, ServiceAccount, Service) and `b2p` (Pod-only drills). Readers choose, or do both |
| `jq`/`yq` in the timed final | **Excluded.** The optional A7 stretch is the only lab task that uses them |
| Exam-environment notes | **Stay in this chapter** (Chapter 39 just cross-references them) |
| Tier 2 tool | Vagrant (not needed for this chapter) |
| Chapter file name | `03-kubectl-fluency.md` (named after the chapter, not `README.md`) |

## 3. Learning objectives

After this chapter the reader can:

1. Install and verify Docker, kind, `kubectl`, and `make`, create the lab cluster, and diagnose a cluster that will not start
2. Explain and edit a kubeconfig; create, switch, and delete contexts; set a default namespace; merge kubeconfigs with `KUBECONFIG`
3. Extract exactly the data needed using `-o wide|yaml|json|name|jsonpath|custom-columns`, `--sort-by`, label selectors, and field selectors, and post-process output with `jq` and `yq`
4. Discover the API offline with `api-resources`, `explain` (including `--recursive`), and `get --raw`
5. Create objects imperatively and generate manifests with `--dry-run=client -o yaml`
6. Choose correctly between `create`, `apply`, `replace`, `edit`, and `patch`, and preview with `diff`
7. Modify live Pods with `label`, `annotate`, `set image`, and `delete`, block on readiness with `wait`, and know which commands (`scale`, `set env`, `set resources`, `rollout`) need a controller and are practised from Chapter 05
8. Check permissions with `kubectl auth can-i`, including impersonation with `--as`
9. Set up a fast terminal: alias, completion, exam variables, `vim`, and (optionally) `tmux`
10. Work through a small timed set of tasks and read their own elapsed time

## 4. Chapter outline

Word counts are targets for the concept text; the lab is separate.

| # | Section | Content | ~Words |
|---|---|---|---|
| 1 | Lab setup | Prerequisites per OS (Linux, macOS, and **WSL2 for Windows**; native PowerShell is out of scope), install commands pinned from `versions.env` (including `jq` and `yq`), `make cluster`, verifying with `kubectl get nodes`, common failures (Docker not running, port conflicts, low memory, WSL2 integration), how to delete and recreate the cluster, hardware requirements per tier | 500 |
| 2 | kubeconfig and contexts | Recap in 3 sentences; the `KUBECONFIG` variable and file merging; `config get-contexts/use-context/set-context/rename-context/delete-context/view --minify`; default namespace per context; why the lab tooling refuses non-kind contexts (safety); exam habit of setting the context first | 450 |
| 3 | Getting exactly the data you need | Output formats; `--show-labels`, `-L`; `--sort-by`; label selectors (equality and set-based) and field selectors; JSONPath (ranges, filters, `{"\n"}`), `custom-columns`; `kubectl get events` sorted by time; caution about `get all`; **`jq` and `yq` in depth** (filtering `-o json` with `jq`, reading and editing YAML with `yq`, and when each beats JSONPath; which `yq` you have matters, see risks) | 950 |
| 4 | Discovering the API | `api-resources` (namespaced vs not, by group), `api-versions`, `explain` and `--recursive`, `get --raw` | 300 |
| 5 | Creating things | Imperative generators (`run`, `create configmap/secret/namespace/serviceaccount`, `expose`); generators for controller kinds (`deployment`, `job`, `cronjob`) shown **with `--dry-run` output only**, to be applied in later chapters; `--dry-run=client` vs `server`; `-o yaml` editing workflow | 450 |
| 6 | Changing things | `create` vs `apply` (client-side vs server-side apply, at a high level) vs `replace` (and `--force`) vs `edit` vs `patch` (strategic, merge, JSON); `diff`; `label`, `annotate`, `set image`; a short note on `scale` and `set env/resources` (they need a controller, so they are demonstrated from Chapter 05); `delete` and deletion flags; `wait --for=`; what cannot be changed on a live Pod (recap from Chapter 04) | 700 |
| 7 | Permissions | `auth can-i` with `--as` and `--list`; what it can and cannot tell you (full RBAC is Chapter 23) | 200 |
| 8 | The fast terminal | `k` alias; bash and zsh completion for the alias; `$do` and `$now` variables; a minimal `~/.vimrc` (2-space indent, expandtab, and so on); `KUBE_EDITOR`; a **short optional box** with a minimal inline `tmux` setup (about five lines, no separate file); history search; bookmarking documentation pages; the **exam-environment notes** (what the real exam typically preconfigures, which tools exist, allowed documentation; **verify against the current candidate handbook before writing**). Chapter 39 links here rather than repeating it | 700 |
| 9 | Command cheat sheet | One-page reference of everything above (also goes to the appendix) | table |
| 10 | Exam tips and common mistakes | | 250 |

## 5. Lab design

The lab has **six parts** (five topics, with two variants of the imperative-creation scenario), selected with a `PART` variable. Each part has its own
setup, reset, verify, and solve, and all obey the contract in `docs/lab-authoring.md`.

```bash
make lab CH=3 PART=a        # shared seeded Pods
make lab CH=3 PART=b1       # context juggling
make lab CH=3 PART=b2       # imperative creation (config objects)
make lab CH=3 PART=b2p      # imperative creation (Pods only)
make lab CH=3 PART=b3       # permission checks
make lab CH=3 PART=final    # timed mini-exam
make verify CH=3 PART=final
make reset  CH=3 PART=b1
```

`make lab CH=3` with no part runs part `a`. `lab.env` lists the available parts
(`LAB_PARTS="a b1 b2 b2p b3 final"`) and each part's namespace as `LAB_NS_<part>`
(used by `make use-namespace` and by the read-only proof in CI; a part that owns
several namespaces lists them all in `LAB_SNAPSHOT_NS`). CI runs the full loop
for every part.

### Part A: shared seeded Pods (guided, computed answers)

**Setup:** namespace `ch03-kubectl` with about eight long-running **Pods only** (no Deployments or other controllers in this chapter's lab), using a
fixed set of labels (`env` = dev/prod, `tier` = web/db), a few different images,
and an `owner` annotation. Labels are assigned by a fixed table so the layout is
deterministic; expected answers are computed from the live cluster by `verify.sh`.

| Task | Skill | Success |
|---|---|---|
| A1 | Label selectors | Names of Pods with `env=prod` and `tier=web`, one per line, to `/tmp/ch03-a1.txt` |
| A2 | `custom-columns` / JSONPath | `name image` for every Pod, sorted by name, to `/tmp/ch03-a2.txt` |
| A3 | Set-based selectors | Names of Pods that are **not** `env=prod`, to `/tmp/ch03-a3.txt` |
| A4 | `annotate` with a selector | Every Pod with `tier=db` carries annotation `reviewed=true` |
| A5 | `--dry-run` + `apply` | Manifest for Pod `api` (image `nginx:1.27`, label `app=api`) saved to `/tmp/ch03-api.yaml` **and** applied |
| A7 | `jq` / `yq` (optional stretch) | Using `jq` on `-o json` **or** `yq` on `-o yaml`, save the sorted, unique list of images in use to `/tmp/ch03-a7.txt`. Marked optional and **not used in the timed final**; `verify.sh` never requires `jq` or `yq` to be installed, it only checks the resulting file against a value computed with `kubectl` alone |
| A6 | `explain` | The type of `pod.spec.terminationGracePeriodSeconds` saved to `/tmp/ch03-a6.txt` |

### Part B: fresh mini-scenarios (each with its own namespace and reset)

| Part | Scenario | Tasks (outcome-checked) | Reset |
|---|---|---|---|
| **b1** Context juggling | Two namespaces, each with a ConfigMap `where` | Create contexts `ch03-a` and `ch03-b` (same cluster and user as the current context, different namespaces); read each ConfigMap's value through its context and save both values to files | Deletes namespaces **and** the two named contexts from the kubeconfig, and restores the original current context and namespace |
| **b2** Imperative creation (config objects) | Namespace with one running Pod `web` | Create ConfigMap `app-config` (two literals), Secret `db-pass`, ServiceAccount `robot`, a run-once Pod `hello` (`--restart=Never`) that prints text, and expose Pod `web` as a Service on port 80 | Deletes the namespace |
| **b2p** Imperative creation (Pods only) | Namespace with Pods `web` (older image tag) and `junk` | (1) `run` Pod `probe` (`busybox:1.36`, command `sleep 3600`, label `role=probe`) in one command; (2) run-once Pod `hello` that prints text and finishes; (3) label `web` with `tier=front` and annotate it `contact=ops`; (4) `set image` on `web` to `nginx:1.27`; (5) `run` Pod `envpod` with env var `APP_MODE=test`; (6) delete `junk` immediately | Deletes the namespace |
| **b3** Permissions | ServiceAccount `viewer` bound to the built-in `view` ClusterRole in its namespace | Using `auth can-i --as`, save `yes` or `no` for: delete Pods, list Secrets, get Pods | Deletes the namespace |

**Which one to do:** `b2p` needs nothing that has not been taught by this point. `b2` creates objects that Chapters 07 and 11 explain properly, so it is best for readers who already know them; the chapter text says so and lets the reader choose. Doing both is encouraged: they practise the same imperative-creation skill. `b2` keeps to Pods plus the small config objects (ConfigMap, Secret, ServiceAccount, Service); it deliberately uses a run-once Pod rather than a Job. Those objects are explained properly in Chapters 07 and 11, and here they are only *created*. b3 introduces RBAC only as a *consumer* (asking "can it?"); Chapter 23 explains
how the permissions are granted.

### Part C: guided drills and a timed final

- **Drills (in the chapter text):** about ten one-line drills with expected outputs, for readers to run in their terminal (for example "print only the image of every Pod in the namespace"). They are self-checked by comparing with the shown output, and are not automated.
- **`final` part (automated):** a fresh six-task mini-exam that mixes skills from A and B across two namespaces, using **Pods only** (no config objects, so it works for readers who chose `b2p`, and it stays free of `jq`/`yq`).
  - `setup.sh` writes a start timestamp to `lab/.state/final-start`.
  - `verify.sh` reports tasks passed **and elapsed time**, with a suggested target of 20 minutes. Time is reported, not enforced, so a slow run still verifies.
  - `reset.sh` rebuilds and restarts the clock.

### Lab tooling changes required first

These small changes to the shared tooling are prerequisites:

1. `tools/run-lab.sh`, `tools/test-lab.sh`, and the `Makefile` accept `PART` and pass it to the lab scripts as `LAB_PART`.
2. `tools/test-lab.sh` loops over every part listed in `LAB_PARTS` (including both `b2` and `b2p`), running the full setup, verify (must fail), solve, verify (must pass), reset, verify (must fail) loop for each.
3. (Done) `tools/lib.sh`: add helpers to **save and restore** the current context and its default namespace (`lab_save_kubectx` / `lab_restore_kubectx`), so labs that switch context or namespace leave the reader's environment as they found it.
4. `docs/lab-authoring.md`: document multi-part labs and the rule that kubeconfig changes must be undone by `reset`.
5. `versions.env`: pin `JQ_VERSION` and `YQ_VERSION` (use **mikefarah/yq v4**, the Go implementation; the Python `yq` has different syntax and must be called out in the text).

## 6. Shell and exam-setup deliverables

These live in `envs/shell/` and are referenced from the chapter. (`tmux` is only an inline optional box in the chapter, so it has no file here.)

| File | Purpose |
|---|---|
| `kubectl-exam.sh` | Sourced from `~/.bashrc` (and zsh): `alias k=kubectl`, completion wired to `k`, `export do="--dry-run=client -o yaml"`, `export now="--force --grace-period 0"`, and `KUBE_EDITOR` |
| `vimrc` | Minimal: 2-space indent, `expandtab`, `number`, sensible YAML behaviour |
| `install.sh` / `uninstall.sh` | Idempotent: add or remove a single marked block in `~/.bashrc` / `~/.zshrc`; never overwrite existing files without a backup. Supports Linux, macOS, and WSL2 only |

Tests for these (in CI): `bash -n` and shellcheck on the scripts; source
`kubectl-exam.sh` in a clean `bash -c` and assert the alias and variables exist;
run install twice and assert the block appears once; run uninstall and assert
the file is restored; check `vim -Es -u envs/shell/vimrc` exits cleanly if `vim`
is available. For the `jq`/`yq` examples in the text, CI runs each example against
sample `kubectl` JSON/YAML output stored in the repo and compares with the shown
expected output.

## 7. Questions (target 15)

- **5 multiple choice** (KCNA and CKA style): what a context contains; `apply` vs `create`; what `--dry-run=client -o yaml` does; which selector syntax means "not in"; what `auth can-i` reports.
- **10 performance tasks** (CKAD and CKA style): JSONPath extraction, custom columns, sort by field, switch context and namespace, generate a manifest, patch a field, label by selector, wait for a condition, impersonated permission check, and one `jq`/`yq` extraction (tagged optional, since tool availability in the exam is not guaranteed).
- Each tagged with exams, each with an explained answer, all original.

## 8. Files to produce

```text
chapters/03-kubectl-fluency/
├── 03-kubectl-fluency.md
├── questions.yaml
├── manifests/                # seed data for part A and the final (Pods only)
└── lab/
    ├── lab.env               # LAB_PARTS, namespaces, answer file paths
    ├── setup.sh reset.sh verify.sh solve.sh   # dispatch on LAB_PART
    ├── parts/{a,b1,b2,b3,final}.sh            # per-part logic
    └── solutions.md
envs/shell/{kubectl-exam.sh,vimrc,install.sh,uninstall.sh}
appendices/kubectl-cheatsheet.md
```

Also update: `docs/coverage-matrix.md`, `docs/lab-authoring.md`,
`tools/*.sh` (per section 5), `Makefile`, `versions.env` (jq, yq), `ROADMAP.md` status.

## 9. Definition of done (in addition to the chapter checklist in `ROADMAP.md`)

- [ ] Every part passes the CI loop on a real kind cluster (not just the stub)
- [ ] `verify.sh` for every part fails on the untouched lab and after `reset`
- [ ] Both b2 variants pass the CI loop independently and neither depends on the other's state
- [ ] `reset` for part b1 restores the reader's original context and namespace (tested)
- [ ] Shell setup installs cleanly on bash and zsh (Linux, macOS, WSL2), and uninstalls cleanly
- [ ] Every `jq` and `yq` example in the text was run with the pinned versions and matches the shown output
- [ ] No lab `verify.sh` requires `jq` or `yq` to be installed
- [ ] Every command in the text was run on the pinned Kubernetes version
- [ ] No check depends on kubectl output formatting that varies between versions
- [ ] A reader new to `kubectl` finishes the timed final; record their time

## 10. Risks and things to verify

| Risk | Mitigation |
|---|---|
| `kubectl` flags change between versions (some `run`/`create` flags have been removed in the past) | Run every command on the pinned version; keep solutions in YAML form where a flag is fragile |
| Completion behaves differently in bash, zsh, and fish | Support bash and zsh explicitly; state that others are unsupported; test both |
| Two different programs are both called `yq` (mikefarah's Go version and a Python wrapper around `jq`) with incompatible syntax | Pin and teach mikefarah/yq v4; show `yq --version` and how to tell which one is installed |
| `jq`/`yq` may not be available in the real exam | Teach built-in `kubectl` tools first; label the `jq`/`yq` material as a convenience with the built-in equivalent shown beside it |
| Editing `~/.bashrc` can annoy readers | Marked block, idempotent, with an uninstaller and a "print, don't install" mode |
| Kubeconfig changes could damage a reader's real setup | Labs touch only contexts prefixed `ch03-`; save and restore the original; the safety check refuses non-lab contexts |
| The exam environment differs from ours (preconfigured aliases, which tools exist, which documentation is allowed) | **Verify against the current candidate handbook before writing the exam-tips text**; word tips as "typically", not as guarantees |
| JSONPath filter expressions behave differently from `jq` | Include tested examples with expected output |
| Timed final feels punishing | Time is reported, not enforced, and the target is a suggestion |

## 11. Resolved questions, and what they changed

| Question | Answer | Effect on this plan |
|---|---|---|
| Cover `jq` and `yq`? | Yes | New section content, an optional lab task (A7), one question, pinned versions, and tests for the examples |
| Include `tmux`? | Optional box only | No `tmux.conf` and no installer support; five inline lines in the text |
| PowerShell? | No; Windows users use WSL2 | Setup instructions and installer cover Linux, macOS, and WSL2 only |
| Deployments in Part A? | No: Pods only, keep it simple | A5 now creates a Pod; Job replaced by a run-once Pod in b2; `scale`, `set env/resources`, and `rollout` are text-only until Chapter 05 |
| Part b2: keep config objects, or go Pod-only? | Both | Two parts, `b2` and `b2p`, each with its own setup, verify, solve, and reset; the chapter text tells readers which to pick |
| `jq`/`yq` stretch in the timed final? | No, stays out | The final is Pods-only and tool-independent |
| Exam-environment paragraph? | Stays in Chapter 03 | Section 8 owns it; Chapter 39 cross-references it. It still needs verification against the current candidate handbook |

### Assumption to confirm

The timed final is **Pods-only** (so it is fair to readers who chose `b2p` and has no `jq`/`yq` dependency). That was my call, not yours. If you would rather the final also include config objects, say so and I will change it.

## 12. Suggested order of work

1. ~~Tooling changes (section 5), with tests.~~ **Done:** `PART` support, `tools/lab-parts.sh`, `tools/test-lib.sh`, kubeconfig save/restore helpers, optional `teardown` action, docs. `JQ_VERSION`/`YQ_VERSION` are left as commented placeholders in `versions.env` because real versions must be verified when the install commands are written.
2. `envs/shell/` files, with tests.
3. Lab parts, one at a time: a, b2p, b2, b3, b1, final (b1 last: it is the riskiest because it edits the kubeconfig; b2p before b2 because it is the simpler variant).
4. Chapter text, then questions, then the cheat sheet.
5. Coverage matrix, roadmap status, then the real-cluster run.
