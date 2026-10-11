# Mock exam: Part II simulator

> **Exams:** CKAD · CKA (performance-based style)
> **Covers:** Chapters 07 to 16 (the exam-style finale of Part II)
> **Time:** 120 minutes · **Questions:** 14 · **Pass mark:** 66%
> **Lab tier:** 1 (kind)

This is a timed, scored simulator in the style of killer.sh. Like killer.sh, it is
meant to be **harder and more hurried than the real exam**. It uses only what
Chapters 07 to 16 teach, and it closes Part II: do it after Chapter 16.

## How it works

```bash
make cluster                  # once, if you have not already
make mock EXAM=part2          # build the exam; the clock starts when it is ready
make mock-score EXAM=part2    # score your answers, as often as you like
make mock-reset EXAM=part2    # start over from scratch
make mock-teardown EXAM=part2 # remove the exam and restore your kubectl settings
```

The rules mirror the real exam environment:

- **Contexts.** The exam creates two contexts, `p2-a` and `p2-b`, on your lab
  cluster. Each question names the context to use. Run that command first, every
  time. Note that `p2-b` has a default namespace (`p2-batch`) and `p2-a` does not.
- **Namespaces.** Each question names its Namespace. Use exactly that one.
- **Answer files.** Answers that are files go under `/tmp/kbook/part2/<question>/`.
  The folders already exist; write exactly the file the question names.
- **Helm.** The helm command is on your path, as in the lab for Chapter 14.
- **Documentation.** Allowed: `kubectl explain`, `--help`, and kubernetes.io/docs
  in a browser, as in the exam. Not allowed: this book's chapters and the
  solutions file, until you have scored.
- **Weights.** Every question has a task weight. A question counts only when
  everything it asks for is right; then you earn its whole weight. Your score is
  the sum. Skipping a hard question to finish the easy ones is a valid strategy.
- **Time.** `make mock-score` shows the time used. It never stops you.

When you are done, run `make mock-score EXAM=part2`, then read
[`lab/solutions.md`](lab/solutions.md) for every question you missed.

> **Exam tip:** Flag and skip. If a question is not going well after twice its fair
> share of time (about 9 minutes here), move on and come back at the end.

---

## Question 1 | Configuration as environment variables

Task weight: 7%

Use context: `kubectl config use-context p2-a`

In Namespace `p2-web`, create a ConfigMap `site-config` with two keys: `THEME`
with the value `dark`, and `LANG` with the value `en`. Create a Pod `site` running
`nginx:1.27` that loads every key of `site-config` as environment variables. The
Pod must be Running.

---

## Question 2 | A Secret in an environment variable

Task weight: 7%

Use context: `kubectl config use-context p2-a`

In Namespace `p2-web`, create a Secret `api-key` of type `Opaque` with one key,
`token`, whose value is `s3-p2-token`. Create a Pod `worker` running
`busybox:1.36` with the command `sleep 3600`. Its environment variable `API_TOKEN`
must come from the key `token` of `api-key`. The Pod must be Running.

---

## Question 3 | A Guaranteed Pod with a readiness probe

Task weight: 8%

Use context: `kubectl config use-context p2-a`

In Namespace `p2-web`, create a Pod `guarded` running `nginx:1.27`. Its CPU and
memory requests must equal its limits: CPU `100m`, memory `64Mi`. Add a readiness
probe that does an HTTP GET on path `/` and port `80`. The Pod must be Ready, and
its QoS class must be `Guaranteed`.

---

## Question 4 | A Job with completions

Task weight: 7%

Use context: `kubectl config use-context p2-b`

In Namespace `p2-batch`, create a Job `migrate` running `busybox:1.36` with the
command `sh -c 'echo migrated'`. It needs 3 completions, one Pod at a time
(parallelism 1), and a backoff limit of 1. The Job must complete.

---

## Question 5 | A CronJob, and a run from it

Task weight: 7%

Use context: `kubectl config use-context p2-b`

In Namespace `p2-batch`, create a CronJob `report` that runs `busybox:1.36` with
the command `sh -c 'echo report'` at `0 3 * * *`. A new run must not start while
the previous one is still running. Then start a Job named `report-now` from the
CronJob, and wait until it completes. Its logs must show `report`.

---

## Question 6 | An init container that writes a value

Task weight: 7%

Use context: `kubectl config use-context p2-b`

In Namespace `p2-data`, create a Pod `pipeline` with an init container `seed`
(image `busybox:1.36`) that writes `42` to `/work/value`. Its main container
`consume` (image `busybox:1.36`, command `sleep 3600`) must read the same file. Both
containers mount the same `emptyDir` volume at `/work`. The Pod must be Running,
and `consume` must print `42` from `/work/value`.

---

## Question 7 | A claim that keeps its data

Task weight: 7%

Use context: `kubectl config use-context p2-b`

In Namespace `p2-data`, create a PersistentVolumeClaim `archive` requesting `200Mi`
with access mode `ReadWriteOnce`, using the default storage class. Create a Pod
`keeper` running `busybox:1.36` with the command `sleep 3600` that mounts `archive`
at `/archive`. The file `/archive/ok` must contain `ok`. The claim must be `Bound`.

---

## Question 8 | A Service with the wrong selector

Task weight: 8%

Use context: `kubectl config use-context p2-a`

In Namespace `p2-edge`, the Deployment `shop` runs two Pods labeled `app=shop`, but
the Service `shop` does not reach them. Fix the Service so that every ready `shop`
Pod is one of its endpoints. Change the Service in place.

---

## Question 9 | An Ingress for a path

Task weight: 7%

Use context: `kubectl config use-context p2-a`

In Namespace `p2-edge`, create an Ingress `shop` with ingress class `nginx` and host
`shop.p2.example.test`. It sends the path `/app` (path type `Prefix`) to the Service
`shop` on port `80`.

---

## Question 10 | A Helm release

Task weight: 7%

Use context: `kubectl config use-context p2-a`

The chart is in `/tmp/kbook/part2/10/chart`. In Namespace `p2-release`, install it as
the release `web` with `replicaCount` set to `2`. The release must be `deployed`, and
the Deployment `web` must have 2 replicas.

---

## Question 11 | A rollback

Task weight: 7%

Use context: `kubectl config use-context p2-a`

In Namespace `p2-release`, the Deployment `api` was changed from `nginx:1.26` to
`nginx:1.27`. Roll it back to its first revision, so that it runs `nginx:1.26` again.

---

## Question 12 | Answer from a crashing Pod

Task weight: 7%

Use context: `kubectl config use-context p2-b`

In Namespace `p2-ops`, the Pod `crash` keeps failing. Find the line it printed that
starts with `fatal`, and save that line, with no other text, to
`/tmp/kbook/part2/12/message.txt`.

---

## Question 13 | A PodDisruptionBudget at the served version

Task weight: 7%

Use context: `kubectl config use-context p2-a`

In Namespace `p2-ops`, create a PodDisruptionBudget `api-guard` that keeps at least
one Pod with the label `app=api` available. Use the API version the cluster serves
for PodDisruptionBudgets.

---

## Question 14 | Relabel some Pods

Task weight: 7%

Use context: `kubectl config use-context p2-a`

In Namespace `p2-ops`, the Pods `tool-1`, `tool-2`, and `tool-3` have the label
`stage=old`. Change their `stage` label to `new`. The Pod `keep` has the label
`stage=keep`, and it must not change.
