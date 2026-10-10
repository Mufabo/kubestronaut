# Mock exam: Part I simulator

> **Exams:** CKAD · CKA (performance-based style)
> **Covers:** Chapters 02 to 06 (all of Part I)
> **Time:** 120 minutes · **Questions:** 18 · **Pass mark:** 66%
> **Lab tier:** 1 (kind)

This is a timed, scored simulator in the style of killer.sh, the simulator the
Linux Foundation includes with the CKAD, CKA, and CKS. Like killer.sh, it is
meant to be **harder and more hurried than the real exam**: if you pass it
comfortably, you know Part I well. It uses only what Chapters 02 to 06 teach,
and it is the exam-style finale of Part I: do it after Chapter 06.

## How it works

```bash
make cluster                  # once, if you have not already
make mock EXAM=part1          # build the exam; the clock starts when it is ready
make mock-score EXAM=part1    # score your answers, as often as you like
make mock-reset EXAM=part1    # start over from scratch
make mock-teardown EXAM=part1 # remove the exam and restore your kubectl settings
```

The rules mirror the real exam environment:

- **Contexts.** The exam creates two contexts, `p1-a` and `p1-b`, on your lab
  cluster. Each question starts with the context to use. Run that command
  first, every time; in the real exam each context is a different cluster, and
  work done in the wrong one scores nothing. Note that `p1-b` has a default
  namespace and `p1-a` does not.
- **Namespaces.** Each question names its Namespace. Use exactly that one.
- **Answer files.** Answers that are files go under `/tmp/kbook/part1/<question>/`.
  The folders already exist; write exactly the file named in the question.
- **Documentation.** Allowed: `kubectl explain`, `--help`, and
  kubernetes.io/docs in a browser, as in the exam. Not allowed: this book's
  chapters and the solutions file, until you have scored.
- **Weights.** Every question has a task weight. A question counts only when
  everything it asks for is right; then you earn its whole weight. Your score
  is the sum. Skipping a hard question to finish the easy ones is a valid
  strategy.
- **Time.** `make mock-score` shows the time used. It never stops you; you
  decide whether you finished within 120 minutes.

When you are done, run `make mock-score EXAM=part1`, then read
[`lab/solutions.md`](lab/solutions.md) for every question you missed.

> **Exam tip:** Flag and skip. If a question is not going well after twice its
> fair share of time (about 13 minutes here), move on and come back at the end.

---

## Question 1 | Contexts

Task weight: 3%

Use context: any

Write the names of all contexts in your kubeconfig into
`/tmp/kbook/part1/1/contexts`, one per line. Write the default namespace of the
context `p1-b` into `/tmp/kbook/part1/1/namespace`.

## Question 2 | Pod with a named container

Task weight: 6%

Use context: `kubectl config use-context p1-a`

Create a single Pod named `courier` of image `nginx:1.27` in Namespace `p1-io`.
The container should be named `courier-container`. The Pod should have the
labels `app=courier` and `tier=edge` and declare container port `80`.

## Question 3 | Fix a crashing Pod

Task weight: 7%

Use context: `kubectl config use-context p1-b`

The Pod `ledger` in Namespace `p1-europa` should run `sleep 3600`, but its
container never stays up. Fix it so it runs. You may delete and recreate the
Pod, but keep its name, image, labels, and annotations.

## Question 4 | Logs of a container that crashed

Task weight: 6%

Use context: `kubectl config use-context p1-a`

The Pod `beacon` in Namespace `p1-titan` has two containers. One of them
crashed once; before it crashed it printed a line `token=<value>`. Write only
the value into `/tmp/kbook/part1/4/token`, and the name of the container that
crashed into `/tmp/kbook/part1/4/container`.

## Question 5 | Requests without a CPU limit

Task weight: 5%

Use context: `kubectl config use-context p1-a`

Create a Pod named `cruncher` in Namespace `p1-titan` with a single container
of image `busybox:1.36` that runs `sleep 3600`. The container should request
`50m` CPU and `32Mi` memory, be limited to `64Mi` memory, and have **no** CPU
limit.

## Question 6 | Exit codes

Task weight: 5%

Use context: `kubectl config use-context p1-b`

In Namespace `p1-io`, create a Pod named `migrate` with a single container of
image `busybox:1.36` that runs `sh -c 'echo migration finished; exit 4'`. The
Pod must never be restarted.

The Pod `importer` in Namespace `p1-io` has already finished. Write the exit
code of its container, as Kubernetes recorded it, into
`/tmp/kbook/part1/6/exit-code`.

## Question 7 | Labels and annotations by selector

Task weight: 5%

Use context: `kubectl config use-context p1-b`

In Namespace `p1-callisto`, add the label `protected=true` to every Pod whose
`tier` label is `db` or `cache`, and to no other Pod. Then annotate every Pod
labelled `env=prod` with `audit=q4-2026`.

## Question 8 | Change and remove labels

Task weight: 4%

Use context: `kubectl config use-context p1-b`

In Namespace `p1-callisto`, change the label `stage=beta` to `stage=ga` on
every Pod that has it, leaving every other `stage` label as it is. Then remove
the label `temp` from every Pod that has it.

## Question 9 | Find information fast

Task weight: 5%

Use context: `kubectl config use-context p1-a`

In Namespace `p1-callisto`:

1. Write the names of all Pods that have **any** container running image
   `nginx:1.26` into `/tmp/kbook/part1/9/pods`, one per line.
2. Write the total number of **containers** across all Pods into
   `/tmp/kbook/part1/9/containers`.

## Question 10 | Generate, edit, create

Task weight: 6%

Use context: `kubectl config use-context p1-a`

Generate a manifest for a Pod named `gateway` with a container named `gateway`
of image `nginx:1.27`, the environment variable `MODE=edge`, and the label
`app=gateway`, and save it to `/tmp/kbook/part1/10/gateway.yaml`. Edit the file
to add a second container named `helper` of image `busybox:1.36` that runs
`sleep 3600`. Then create the Pod in Namespace `p1-io` from that file.

## Question 11 | Config objects

Task weight: 6%

Use context: `kubectl config use-context p1-b`

In Namespace `p1-europa`, create:

1. A ConfigMap `ledger-config` with `currency=EUR` and `rounding=half-even`.
2. A generic Secret `ledger-db` with `user=ledger` and `password=l3dg3r-pw`.
3. A ServiceAccount `ledger-sa`.
4. A Service `ledger-svc` that exposes the Pod `ledger` on port `8080`,
   forwarding to container port `80`.

## Question 12 | Ask the API

Task weight: 4%

Use context: `kubectl config use-context p1-a`

1. Write the API group and version that serve **CronJobs**, in the form
   `group/version`, into `/tmp/kbook/part1/12/cronjob-api`.
2. Write the type of the field `runAsNonRoot` in a container's
   `securityContext` (for example `string`) into
   `/tmp/kbook/part1/12/run-as-non-root`.
3. Are Namespace objects themselves namespaced? Write `yes` or `no` into
   `/tmp/kbook/part1/12/namespaced`.

## Question 13 | Permissions

Task weight: 6%

Use context: `kubectl config use-context p1-a`

The ServiceAccount `auditor` in Namespace `p1-titan` has some permissions.
Answer these four questions about it, one word per line (`yes` or `no`), in
this order, in `/tmp/kbook/part1/13/answers`:

1. Can it list Pods in `p1-titan`?
2. Can it get Secrets in `p1-titan`?
3. Can it create Pods in `p1-io`?
4. Can it list Pods in `p1-io`?

## Question 14 | How the control plane runs

Task weight: 6%

Use context: `kubectl config use-context p1-a`

1. Write the image of the kube-apiserver, including its tag, into
   `/tmp/kbook/part1/14/apiserver-image`.
2. The kube-proxy Pods are managed by another object. Write that object's kind
   into `/tmp/kbook/part1/14/proxy-owner`.
3. The CoreDNS Pods are managed by a chain of objects. Write the kind of the
   **top** of that chain into `/tmp/kbook/part1/14/dns-owner`.

## Question 15 | A Deployment in a new Namespace

Task weight: 7%

Use context: `kubectl config use-context p1-b`

Create a Namespace `p1-staging` with the label `env=staging`. In it, create a
Deployment named `relay` with 3 replicas of image `nginx:1.27`. Its single
container must be named `relay-container`. Wait until all replicas are ready.

## Question 16 | Roll back a broken release

Task weight: 7%

Use context: `kubectl config use-context p1-a`

The latest rollout of the Deployment `atlas` in Namespace `p1-ganymede` is
stuck. Roll `atlas` back to the last revision that worked, without deleting
and recreating it. Write the number of the revision that broke it into
`/tmp/kbook/part1/16/broken-revision`.

## Question 17 | A careful update

Task weight: 6%

Use context: `kubectl config use-context p1-a`

Update the Deployment `orbit` in Namespace `p1-ganymede` to image
`nginx:1.27`, with a rolling update that never has fewer ready Pods than
wanted and adds at most one extra Pod at a time. Record the change cause
`orbit to 1.27`. Do not delete and recreate the Deployment, and wait until the
rollout is complete.

## Question 18 | Quarantine a Pod

Task weight: 6%

Use context: `kubectl config use-context p1-b`

One Pod of the Deployment `drone` in Namespace `p1-ganymede` carries the
annotation `quarantine=yes`. Take it out of the Deployment for investigation,
without deleting it, by changing its label `app=drone` to
`app=drone-quarantine`. The Deployment must be back to 3 ready Pods.
