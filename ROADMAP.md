# ROADMAP: The Kubestronaut Textbook

A hands-on textbook covering everything needed for the five certifications that make up **Kubestronaut**: **KCNA, KCSA, CKAD, CKA, CKS**.

- **Audience:** readers who already know Linux, basic web development, and containers.
- **Format:** one Markdown file per chapter, plus setup files for each chapter's lab environment.
- **Labs:** KodeKloud/Killercoda-style, repeatable and resettable with one command, self-checking.
- **Assessment:** end-of-chapter questions in every chapter, plus a mock exam per certification.

> **Before locking the outline:** verify each certification's current curriculum (domains, weights, Kubernetes version) on the CNCF/Linux Foundation curriculum repos. Update `docs/coverage-matrix.md` (see §6) whenever they change.
> **Already checked:** KCNA now has four domains (44/28/16/12) and CKA has five (25/15/20/10/30), per the official `cncf/curriculum` READMEs. The bullet-level PDFs still need to be transcribed into the coverage matrix.

---

## 1. Guiding principles

1. **Teach by topic, tag by exam.** The five exams overlap heavily. Chapters are organized by subject; each chapter declares which exams it serves.
2. **Every lab is disposable.** A reader can break anything and be back at the starting state in under a minute.
3. **Every lab is verifiable.** Each task has an automated check, so readers get instant PASS/FAIL feedback.
4. **Every lab is tested in CI.** If the reference solution does not pass `verify.sh` in CI, the chapter does not merge.
5. **Speed matters.** The performance-based exams are timed. Labs teach imperative `kubectl`, docs navigation, and time budgeting from Part I onward, not just in the exam-prep part.
6. **One version pin.** The Kubernetes version and all tool versions live in a single `versions.env`.

---

## 2. Repository layout

```
kubestronaut-book/
├── ROADMAP.md
├── versions.env                 # K8s version + pinned tool versions
├── Makefile                     # make lab / reset / verify / solve CH=07
├── docs/
│   ├── style-guide.md
│   ├── chapter-template.md
│   ├── coverage-matrix.md       # every curriculum bullet -> chapter + lab
│   └── lab-authoring.md         # conventions for setup/reset/verify scripts
├── tools/
│   ├── lib.sh                   # shared shell helpers (log, assert, wait)
│   ├── render-questions.py      # questions/*.yaml -> chapter markdown
│   └── lint/                    # markdown + shellcheck + yamllint config
├── envs/
│   ├── kind/                    # Tier 1 cluster configs
│   ├── vagrant/                 # Tier 2 multi-VM kubeadm environment
│   └── devcontainer/            # Tier 3 Codespaces / hosted option
├── chapters/
│   └── 07-configmaps-secrets/
│       ├── 07-configmaps-secrets.md  # the chapter text (named after the chapter)
│       ├── questions.yaml       # end-of-chapter question bank
│       ├── manifests/           # starter YAML for the reader
│       └── lab/
│           ├── lab.env          # LAB_NS, LAB_TIER, ...
│           ├── setup.sh         # idempotent: builds the starting state
│           ├── reset.sh         # returns to the starting state
│           ├── verify.sh        # per-task PASS/FAIL
│           ├── solve.sh         # automated reference solution (CI)
│           └── solutions.md     # human-readable, kept separate to avoid spoilers
├── mock-exams/
│   ├── kcna/  kcsa/  ckad/  cka/  cks/
└── appendices/
```

---

## 3. Lab infrastructure

| Tier | Environment | Used for | Reset method |
|---|---|---|---|
| 1 | kind / k3d (multi-node) on the reader's machine | ~70% of chapters: workloads, config, services, storage, RBAC, scheduling | Delete namespace, or delete and recreate the cluster |
| 2 | Multi-VM kubeadm cluster (**Vagrant**, decided) | Cluster install, upgrades, etcd backup/restore, node troubleshooting, most of CKS (AppArmor, seccomp, Falco, kernel-level work) | Restore VM snapshot |
| 3 | Devcontainer / Codespaces / Killercoda scenarios | Readers without capable hardware | Rebuild container / restart scenario |

**Reset contract** (identical in every chapter):

| Script | Behavior |
|---|---|
| `setup.sh` | Idempotent. Creates the exact starting state. Safe to run repeatedly. |
| `reset.sh` | Tears down chapter resources and re-runs `setup.sh`. |
| `verify.sh` | Runs one check per task; prints `PASS`/`FAIL` with a hint; exits non-zero on any failure. |
| `solve.sh` | Automated reference solution; CI applies it to prove `verify.sh` can pass. |
| `solutions.md` | Step-by-step solutions, one per task, in a separate file. |

Each lab runs in its own namespace (Tier 1) or snapshot (Tier 2) so that chapters never interfere with each other.

**Hardware requirements to state in Chapter 3:** Tier 1 needs roughly 4 GB RAM free; Tier 2 needs roughly 8 to 16 GB. Point everyone else to Tier 3.

---

## 4. Chapter template

Every chapter follows this structure:

1. **Header block:** exams served (tags), difficulty, estimated time, lab tier, prerequisites
2. **Learning objectives** (mapped to curriculum bullets)
3. **Concepts:** explanation with Mermaid diagrams
4. **Guided walkthrough:** commands with expected output
5. **Hands-on lab:** 3 to 6 tasks, each with a suggested time limit and difficulty label
6. **Exam tips:** imperative shortcuts, which docs pages to bookmark
7. **End-of-chapter questions:** 10 to 15 (multiple choice for KCNA/KCSA style; performance tasks for CKA/CKAD/CKS style)
8. **Further reading**

### Chapter definition of done

- [ ] Text reviewed against the current curriculum bullets it claims to cover
- [ ] All commands executed on the pinned Kubernetes version
- [ ] `setup.sh`, `reset.sh`, `verify.sh` implemented and idempotent
- [ ] CI run: setup, apply reference solution, `verify.sh` passes
- [ ] CI run: `verify.sh` fails on the untouched starting state (proves the checks are real)
- [ ] `reset.sh` verified after a deliberately broken lab
- [ ] Questions written, each with an explanation of the correct answer
- [ ] Coverage matrix updated
- [ ] Read by one person at the target level who was not the author

---

## 5. Chapter plan

Legend: **A** = KCNA, **S** = KCSA, **D** = CKAD, **C** = CKA, **X** = CKS. Tier = lab environment (1, 2, or none for conceptual).

### Part I: Foundations

| # | Chapter | Exams | Tier |
|---|---|---|---|
| 01 | Cloud-native landscape, the CNCF, and why Kubernetes exists | A | none |
| 02 | Kubernetes architecture: control plane, nodes, API server, etcd | A C | 1 |
| 03 | Lab setup and `kubectl` fluency (contexts, output formats, `explain`, dry-run) | A D C | 1 |
| 04 | Pods in depth | A D C | 1 |
| 05 | Controllers: ReplicaSets, Deployments, rollouts and rollbacks | A D C | 1 |
| 06 | Namespaces, labels, selectors, annotations | A D C | 1 |

### Part II: Building and running applications

| # | Chapter | Exams | Tier |
|---|---|---|---|
| 07 | ConfigMaps, Secrets, environment variables, downward API | D C | 1 |
| 08 | Jobs and CronJobs | D | 1 |
| 09 | Multi-container pods: init containers, sidecars, patterns | D | 1 |
| 10 | Probes, requests/limits, QoS classes | D C | 1 |
| 11 | Services and cluster DNS | A D C | 1 |
| 12 | Ingress and Gateway API | D C | 1 |
| 13 | Storage basics: volumes, PV, PVC, StorageClass | D C | 1 |
| 14 | Helm and Kustomize | D C | 1 |
| 15 | Developer observability: logs, metrics, debugging applications | A D | 1 |
| 16 | Application delivery: CI/CD, GitOps (Argo CD, Flux), deployment strategies | A D | 1 |

### Part III: Cluster administration

| # | Chapter | Exams | Tier |
|---|---|---|---|
| 17 | Scheduling: taints, tolerations, affinity, topology spread, priority, static pods | C | 1 |
| 18 | Installing a cluster with kubeadm | C | 2 |
| 19 | Cluster upgrades and node maintenance (cordon, drain) | C | 2 |
| 20 | etcd backup and restore | C | 2 |
| 21 | Networking internals: CNI, kube-proxy, NetworkPolicy, CoreDNS | A C | 1/2 |
| 22 | Storage internals: CSI, dynamic provisioning, access modes | C | 1 |
| 23 | RBAC and ServiceAccounts | C X | 1 |
| 24 | CRDs, operators, and extension interfaces (CRI, CNI, CSI) | A C | 1 |
| 25 | Autoscaling: HPA, VPA, cluster autoscaler concepts | A C | 1 |
| 26 | Troubleshooting I: applications and networking | C | 1/2 |
| 27 | Troubleshooting II: nodes, kubelet, control plane, certificates | C | 2 |
| 28 | Cloud-native architecture: service mesh, serverless, personas, community and governance | A | none |

### Part IV: Security

| # | Chapter | Exams | Tier |
|---|---|---|---|
| 29 | Cloud-native security model: 4Cs, threat modeling, compliance frameworks | S | none |
| 30 | Cluster setup hardening: CIS benchmark (kube-bench), API server flags, TLS | S X | 2 |
| 31 | AuthN, AuthZ, and admission control (ValidatingAdmissionPolicy, OPA Gatekeeper, Kyverno) | S X | 1/2 |
| 32 | System hardening: AppArmor, seccomp, host OS footprint | X | 2 |
| 33 | Microservice hardening: Pod Security Standards, securityContext, secrets management, sandboxed runtimes | S X | 2 |
| 34 | Supply chain security: image scanning, signing, SBOMs, image admission policy | S X | 1/2 |
| 35 | Runtime security, monitoring, and auditing: Falco, audit logs, immutability, incident response | S X | 2 |
| 36 | Network security in depth: default-deny, mTLS, encryption in transit | S X | 1/2 |

### Part V: Exam readiness

| # | Chapter | Exams | Tier |
|---|---|---|---|
| 37 | Terminal speed: aliases, `vim`, `tmux`, `jq`/`yq`, imperative commands | D C X | 1 |
| 38 | Navigating the allowed documentation | D C X | none |
| 39 | Exam logistics and study plans per certification | all | none |
| M1-M5 | Mock exams: KCNA, KCSA (question banks); CKAD, CKA, CKS (timed performance-based) | all | 1/2 |

### Appendices

Command cheat sheet · YAML snippets · JSONPath reference · glossary · solution index · troubleshooting the lab environments

---

## 6. Coverage matrix

Maintain `docs/coverage-matrix.md` as a table with one row per curriculum bullet:

| Exam | Domain | Bullet (verbatim from curriculum) | Chapter | Lab task | Question IDs | Status |
|---|---|---|---|---|---|---|

This is the proof of "covers all materials." Review it at the end of every phase and before every release.

---

## 7. Phases and milestones

Estimates assume one author working part-time; adjust for your pace and any co-authors.

### Phase 0: Foundations (2 to 3 weeks)
*Hardening pass done after external review: exact-context plus cluster-marker safety check, no implicit kubeconfig changes (`make use-namespace` is opt-in, `make teardown` restores), CI proofs that `verify` is read-only and that unrelated cluster state survives, question-bank schema validation, cluster version-drift check, and a framework test harness. Still never run against a real kind cluster.*

*Status: scaffold, docs, tooling, CI, and the pilot chapter (04) are drafted. Remaining: run the pilot against a real kind cluster and fix what breaks.*

- [ ] Style guide, chapter template, lab-authoring guide
- [ ] Repo skeleton, `versions.env`, Makefile targets (`lab`, `reset`, `verify`, `solve`)
- [ ] Shared shell library (`tools/lib.sh`) with assertion and wait helpers
- [ ] CI pipeline: markdown lint, shellcheck, yamllint, kind-based lab runner
- [ ] Question-bank format and renderer
- [ ] Coverage matrix populated from all five current curricula (empty status)
- [ ] **Pilot chapter (Ch. 04) finished to the full definition of done**
- **Exit criterion:** a stranger can clone the repo, run `make lab CH=04`, complete the lab, break it, and `make reset CH=04`.

### Phase 1: Parts I and II (~8 weeks)
*Status: Chapters 01 to 04 are drafted. Chapter 02 has a read-only cluster-tour lab; Chapter 03 (kubectl fluency) has a six-part lab (a, b1, b2, b2p, b3, final), the practice-shell files in `envs/shell/`, a jq/yq example test, and a cheat-sheet appendix; Chapter 04 is the Pods pilot. All lab scripts pass the framework test loop against a fake `kubectl` and the jq/yq examples pass with the real tools, but nothing has been run against a real kind cluster yet, and the example output shown for `kubectl` commands in the chapters is unverified.*
- [ ] Chapters 01 to 16 drafted, tested, reviewed
- [ ] Tier 3 devcontainer working
- **Exit criterion:** all Tier 1 labs pass the CI loop; coverage matrix shows KCNA and CKAD material complete.

### Phase 2: Part III (~8 weeks)
- [ ] Tier 2 environment built first: Vagrant config, base-image build, snapshot-based reset
- [ ] Chapters 17 to 28
- **Exit criterion:** a full kubeadm cluster can be rebuilt from scratch, upgraded, and restored from an etcd backup by following the book alone.

### Phase 3: Part IV (~8 weeks)
- [ ] Chapters 29 to 36; pin and test Trivy, Falco, kube-bench, Kyverno/Gatekeeper versions
- **Exit criterion:** every CKS and KCSA bullet in the coverage matrix is mapped and tested.

### Phase 4: Part V and mock exams (~4 weeks)
- [ ] Chapters 37 to 39
- [ ] Five mock exams; time-test each yourself and record how long it took
- **Exit criterion:** mock exams reflect exam format and difficulty, and a beta reader finishes a mock within the allotted time on a first attempt only after studying the book.

### Phase 5: Beta and release (4+ weeks)
- [ ] Recruit 3 to 5 beta readers at the target level
- [ ] Collect stuck-points per chapter; fix environment bugs first, prose second
- [ ] Full re-verification against current curricula and Kubernetes version
- [ ] Release v1.0; publish errata process

**Total:** roughly 8 to 10 months part-time. Labs and environments take more effort than the prose.

---

## 8. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Curriculum or Kubernetes version changes mid-project | Single `versions.env`; coverage matrix; CI re-runs all labs on a version bump |
| Lab scripts rot over time | Every lab in CI; scheduled weekly CI run against pinned and latest versions |
| Verifier scale: ~100 hand-written `verify.sh` files become a maintenance burden | Revisit around 15 labs: if the same check patterns keep repeating, add a declarative `checks:` schema (resource, field, equals) for the simple cases and keep custom shell for behavioural ones. Not worth building at 3 labs |
| Tier 2 hardware requirements exclude readers | Tier 3 hosted option; document minimum specs clearly |
| Labs work on the author's machine only | Beta readers on Linux, macOS, and Windows (WSL2); CI on Linux |
| Security tooling (Falco, Trivy) changes quickly | Pin versions; isolate tool setup in per-chapter `setup.sh` |
| Scope creep (topics beyond the exams) | Every section must map to a coverage-matrix row, or go in "Further reading" |
| Copying exam content | Write original questions and scenarios from the public curricula only; never reproduce real exam questions |

---

## 9. Immediate next steps

1. ~~Decide the Tier 2 tool~~ Decided: **Vagrant**. (Note: Vagrant needs a provider such as VirtualBox or libvirt; the setup guide must say which are supported per OS. Apple Silicon Macs are the awkward case.)
2. Write `docs/chapter-template.md` and `docs/lab-authoring.md`.
3. Build the Makefile and `tools/lib.sh`.
4. Write the pilot chapter (04: Pods) end to end.
5. Set up CI and make the pilot chapter pass the setup, solve, verify loop.
6. Run the Pods lab on a real kind cluster (`make cluster && make test CH=4`), then fix whatever breaks. The stub-`kubectl` test only proves the script logic.
