# Kubestronaut: a hands-on textbook

A hands-on textbook covering the material for all five Kubestronaut
certifications (KCNA, KCSA, CKAD, CKA, CKS). See [ROADMAP.md](ROADMAP.md) for the
plan and status.

## Quick start (Tier 1 labs)

Prerequisites: Docker (or another kind-compatible container runtime), `kind`,
`kubectl`, `make`, and `bash`.

```bash
make cluster          # create the kind lab cluster (once); also marks it as a lab cluster
make lab CH=4         # start chapter 4's lab (does not touch your kubectl settings)
make verify CH=4      # check your work
make reset CH=4       # back to the starting state, any time
make solve CH=4       # reference solution (spoilers!)
make use-namespace CH=4   # optional: make kubectl default to the lab namespace
make teardown CH=4    # remove the lab and restore your kubectl settings
```

Run `make help` for everything else. Author-facing docs are in `docs/`.
