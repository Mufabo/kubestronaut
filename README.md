# Kubestronaut: a hands-on textbook

A hands-on textbook covering the material for all six Kubestronaut
certifications: KCNA, KCSA, CKAD, CKA, CKS, and the CKNE (Certified Kubernetes
Network Engineer). Parts I to IV cover the first five; Parts V to X cover the
CKNE, starting from zero networking knowledge; Part XI prepares you for the
exams. See [ROADMAP.md](ROADMAP.md) for the plan and status.

## Reading orders

Reading the book front to back covers all six exams. To prepare for one exam,
read only the chapters below, in this order. Chapters marked † run their labs
on the Tier 2 VMs (`envs/vagrant`) instead of the kind cluster; the others need
only the kind cluster, or nothing for concept chapters. Every path ends with
Chapters 73 (the allowed documentation) and 74 (exam logistics and study
plans), and with the mock exams listed; see [`mock-exams/`](mock-exams/README.md).

### KCNA (multiple choice)

1. Part I: 01 Cloud-native landscape, 02 Architecture, 03 kubectl, 04 Pods, 05 Controllers, 06 Namespaces and labels
2. Part II: 11 Services and DNS, 15 Observability and API deprecations, 16 Images and delivery
3. Part III: 21 Networking internals, 24 CRDs and extension interfaces, 28 Cloud-native architecture
4. Part IV: 29 Security model, 33 Microservice hardening (Pod Security Standards)
5. Chapter 74; mock exams `kcna` and `kcna2` (`make quiz EXAM=kcna`)

The KCNA has no lab, so the labs in these chapters are optional practice. The
end-of-chapter questions tagged `KCNA` are the ones in its style.

### CKAD (performance-based)

1. Part I: 02 to 06
2. Part II: 07 ConfigMaps and Secrets, 08 Jobs, 09 Multi-container Pods, 10 Probes, resources, and securityContext, 11 Services, 12 Ingress and Gateway API, 13 Storage, 14 Helm and Kustomize, 15 Observability, 16 Images and delivery
3. Part XI: 72 Terminal speed, 73, 74
4. Mock exams `part1`, `part2`, then `ckad` and `ckad2`

### CKA (performance-based)

1. Part I: 02 to 06
2. Part II: 07, 10, 11, 12, 13, 14 (08, 09, 15, and 16 are CKAD material; skip them)
3. Part III: 17 Scheduling, 18 kubeadm †, 19 Upgrades †, 20 etcd backup †, 21 Networking internals, 22 Storage internals, 23 RBAC, 24 CRDs and operators, 25 Autoscaling, 26 Troubleshooting I, 27 Troubleshooting II † (28 is KCNA material)
4. Part XI: 72, 73, 74
5. Mock exams `part1`, `part2`, `part3` †, then `cka` † and `cka2` †

### KCSA (multiple choice)

1. Part I: 01, 02
2. Part III: 21 Networking internals, 23 RBAC
3. Part IV: 29 Security model, 30 Cluster hardening †, 31 AuthN, AuthZ, and admission, 32 System hardening †, 33 Microservice hardening †, 34 Supply chain, 35 Runtime security †, 36 Network security
4. Chapter 74; mock exam `kcsa` (`make quiz EXAM=kcsa`)

Like the KCNA, the KCSA has no lab: read the Concepts sections of Part IV
closely, and treat the labs as optional.

### CKS (performance-based)

The CKS requires an active CKA, so this path assumes the CKA path above.

1. Refresh: 19 Upgrades †, 23 RBAC
2. Part IV: 29 to 36 (30, 32, 33, and 35 †)
3. Part XI: 73, 74
4. Mock exam `cks` †

### CKNE (performance-based)

The CKNE assumes CKA-level Kubernetes (at least Chapters 02 to 06, 11, 12, and 21).
Only Chapters 37 to 54 are written so far; see [ROADMAP.md](ROADMAP.md).

1. Part V, networking from zero: 37 to 47, in the netlab container. If you already know networking, take the `part5` quiz first and read only the chapters whose questions you miss.
2. Part VI, Core Infrastructure and CNI: 48 to 52; mock exam `part6`
3. Parts VII to X: 53 onward, as they are written (each Part ends with its mock exam)
4. Part XI: 73, 74

### All six (Kubestronaut)

A common order is KCNA, CKAD, CKA, KCSA, CKS, then CKNE: each exam builds on
the one before, and the two multiple-choice exams come first in their area.
Read in that order, the paths above share their chapters, so after the first
pass you only add each exam's new chapters.

## Quick start (Tier 1 labs)

Prerequisites: Docker (or another kind-compatible container runtime), `kind`,
`kubectl`, `make`, and `bash`.

```bash
make cluster          # create the kind lab cluster (once); also marks it as a lab cluster
make lab CH=4         # start chapter 4's lab and show task 1 (does not touch your kubectl settings)
make check CH=4       # check the current task; if it is right, show the next one
make question CH=4    # show the current task again
make verify CH=4      # check every task at once
make reset CH=4       # back to the starting state, any time
make solve CH=4       # reference solution (spoilers!)
make use-namespace CH=4   # optional: make kubectl default to the lab namespace
make teardown CH=4    # remove the lab and restore your kubectl settings
```

Labs work like KodeKloud's: one task at a time, a check after each, and
progress that is saved between sessions. Each Part of the book ends with a
mock exam that works like the killer.sh exam simulator instead: weighted
questions, a context per question, all scored at once.

## Mock exams

Timed, scored simulators with several contexts and a pass mark. See
[`mock-exams/`](mock-exams/README.md).

```bash
make mock EXAM=part1          # the clock starts when it is ready
make mock-score EXAM=part1
make mock-teardown EXAM=part1
```

## Part V: the netlab (Tier 0)

Part V ("Networking from zero") runs its labs in one Docker container in which
you build small networks; it needs only Docker.

```bash
make netlab           # build the image (once) and start the container
make lab CH=38        # start a Part V lab; the loop is the same as above
make shell            # a shell inside the lab, where you do the tasks
```

From Part VI on, the labs use the kind cluster again, built from a **profile**
(`calico` by default, `nocni` or `cilium` for the CKNE chapters). A lab rebuilds
the cluster when it needs another profile; `make cluster-status` shows the
current one and `make cluster` goes back to the default.

Run `make help` for everything else. Author-facing docs are in `docs/`.
