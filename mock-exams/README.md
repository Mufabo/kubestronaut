# Mock exams

Timed, scored exam simulators in the style of killer.sh. Each one builds its
own Namespaces and kubectl contexts on your lab cluster, gives you a fixed
time and a pass mark, and scores the weighted questions all at once. A
question counts when everything it asks for is right.

| Exam | Covers | Questions | Time | Pass mark |
| --- | --- | --- | --- | --- |
| [`part1`](part1/part1.md) | Part I (Chapters 02 to 06), CKAD/CKA style | 18 | 120 min | 66% |
| [`part2`](part2/part2.md) | Part II (Chapters 07 to 16), CKAD/CKA style | 14 | 120 min | 66% |

The full CKAD, CKA, and CKS simulators (and the KCNA and KCSA question banks)
come with Part V; see `ROADMAP.md`.

```bash
make cluster                       # once
make mock EXAM=part1               # build the exam; the clock starts when it is ready
make mock-score EXAM=part1         # score, as often as you like
make mock-reset EXAM=part1         # start over
make mock-solve EXAM=part1         # reference solution (spoilers!)
make mock-teardown EXAM=part1      # remove it and restore your kubectl settings
```

Each exam's questions are in `<name>/<name>.md` and its worked solutions in
`<name>/lab/solutions.md`. Read the solutions only after you have scored.
