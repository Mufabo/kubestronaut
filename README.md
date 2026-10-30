# Kubestronaut: a hands-on textbook

A hands-on textbook covering the material for all five Kubestronaut
certifications (KCNA, KCSA, CKAD, CKA, CKS). See [ROADMAP.md](ROADMAP.md) for the
plan and status.

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

Run `make help` for everything else. Author-facing docs are in `docs/`.
