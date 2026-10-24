# Mock exams

Timed, scored exam simulators. The full CKA and CKS simulators and the KCSA
practice exam come with Part V; see `ROADMAP.md`.

## Multiple-choice practice exams

The KCNA has no lab; its practice exam runs in the terminal (`tools/quiz.py`),
timed and scored like the real one, with the questions in a new order each
attempt.

| Exam | Covers | Questions | Time | Pass mark |
| --- | --- | --- | --- | --- |
| [`kcna`](kcna/kcna.md) | The four KCNA domains, weighted as in the curriculum | 60 | 90 min | 75% |

```bash
make quiz EXAM=kcna          # start or resume; answer with a letter, flag, review, submit
make quiz-reset EXAM=kcna    # throw the attempt away
```

## Performance-based mock exams

In the style of killer.sh. Each one builds its own Namespaces and kubectl
contexts on your lab cluster, gives you a fixed time and a pass mark, and
scores the weighted questions all at once. A question counts when everything
it asks for is right.

| Exam | Covers | Questions | Time | Pass mark |
| --- | --- | --- | --- | --- |
| [`part1`](part1/part1.md) | Part I (Chapters 02 to 06), CKAD/CKA style | 18 | 120 min | 66% |
| [`part2`](part2/part2.md) | Part II (Chapters 07 to 16), CKAD/CKA style | 14 | 120 min | 66% |
| [`part3`](part3/part3.md) | Part III (Chapters 17 to 28), CKA style, on the Tier 2 VMs | 16 | 120 min | 66% |
| [`ckad`](ckad/ckad.md) | The full CKAD: every domain, weighted as in the curriculum | 20 | 120 min | 66% |

```bash
make cluster                       # once
make mock EXAM=part1               # build the exam; the clock starts when it is ready
make mock-score EXAM=part1         # score, as often as you like
make mock-reset EXAM=part1         # start over
make mock-solve EXAM=part1         # reference solution (spoilers!)
make mock-teardown EXAM=part1      # remove it and restore your kubectl settings
```

`part3` runs on `cp1` of the Tier 2 VMs instead of the kind cluster, from the
`cluster-prev` snapshot; its question file explains the setup. To start it over,
restore that snapshot on the host.

Each exam's questions are in `<name>/<name>.md` and its worked solutions in
`<name>/lab/solutions.md`. Read the solutions only after you have scored.
