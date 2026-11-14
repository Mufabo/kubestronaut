# Mock exam: CKA simulator, set 2

> **Exam:** CKA (performance-based style)
> **Covers:** every CKA domain, weighted as in the curriculum: Cluster Architecture, Installation and Configuration 25%, Workloads and Scheduling 15%, Services and Networking 20%, Storage 10%, Troubleshooting 30%
> **Time:** 120 minutes · **Questions:** 18 · **Pass mark:** 66%
> **Lab tier:** 2 (the VMs, snapshot `cluster`)

A second, independent CKA simulator: 18 new questions, none repeated from set 1
(`mock-exams/cka`) or the Part III mock. Take set 1 first; when you retake an exam
you remember its answers, so a fresh set is the honest measure in the last week.
Like killer.sh, it is meant to be **harder and more hurried than the real exam**.

## How it works

The exam runs on `cp1` of the Tier 2 VMs, from the `cluster` snapshot. On the host:

```bash
make cluster-pause                       # in WSL, if the kind cluster runs: frees RAM
envs/vagrant/kbook-vm restore cluster    # Windows: .\envs\vagrant\kbook-vm.ps1 restore cluster
envs/vagrant/kbook-vm ssh                # a shell on cp1
```

Then, on `cp1`:

```bash
cd /kbook
make mock EXAM=cka2            # build the exam; the clock starts when it is ready
make mock-score EXAM=cka2      # score your answers, as often as you like
make mock-teardown EXAM=cka2   # remove the exam and restore your kubectl settings
```

Setup installs Helm, `etcdctl`, and the Gateway API CRDs if they are missing, and
takes a few minutes. The rules are those of set 1:

- **Contexts.** The exam creates two contexts, `cka2-a` and `cka2-b`. Each question
  names the context to use. Run that command first, every time. `cka2-b` has a
  default namespace (`cka2-work`); `cka2-a` does not.
- **Nodes.** Work on `cp1`. Reach the workers with `ssh node1` and `ssh node2`, and use
  `sudo` where a task needs root.
- **Files.** Files a question starts from, and answers that are files, are under
  `/tmp/kbook/cka2/<question>/`. Write exactly the file the question names.
- **Documentation.** Allowed: `kubectl explain`, `--help`, `man`, and the
  documentation Chapter 38 lists for the CKA. Not allowed: this book's chapters and
  the solutions file, until you have scored.
- **Weights.** A question counts only when everything it asks for is right; then you
  earn its whole weight.
- **Time.** `make mock-score` shows the time used. It never stops you.

When you are done, run `make mock-score EXAM=cka2`, then read
[`lab/solutions.md`](lab/solutions.md) for every question you missed.

---

## Question 1 | A user, a certificate, and a kubeconfig

Task weight: 7%

Use context: `kubectl config use-context cka2-a`

Create credentials for a user `dev`, without a CertificateSigningRequest object: a
private key `/tmp/kbook/cka2/1/dev.key`, and a client certificate
`/tmp/kbook/cka2/1/dev.crt` with the common name `dev`, signed directly by the
cluster's CA on `cp1` and valid for 30 days. Then write a kubeconfig
`/tmp/kbook/cka2/1/dev.kubeconfig` whose current context uses these credentials, the
API server at `https://192.168.56.10:6443` with the cluster's CA, and the default
Namespace `cka2-dev`. Finally, let `dev` use the ClusterRole `edit` in `cka2-dev`, and
nowhere else.

---

## Question 2 | Reports for everyone who may view

Task weight: 6%

Use context: `kubectl config use-context cka2-a`

The cluster has a custom resource `reports.cka2.kbook.io`. The group `analysts` may
`view` the Namespace `cka2-team`, but the `view` ClusterRole does not cover reports.
Create a ClusterRole `cka2-reports-viewer` that allows `get`, `list`, and `watch` on
reports, and is aggregated into `view`, so that everyone with `view` can read them.

---

## Question 3 | Install a component with Kustomize

Task weight: 7%

Use context: `kubectl config use-context cka2-a`

`/tmp/kbook/cka2/3/components.yaml` is the release manifest of metrics-server. On
these nodes it must run with the argument `--kubelet-insecure-tls`. Without editing
`components.yaml`, write `/tmp/kbook/cka2/3/kustomization.yaml` that uses it and adds
the argument with a patch, and install it with Kustomize. The metrics API must work
(`kubectl top nodes`).

---

## Question 4 | A failed release

Task weight: 5%

Use context: `kubectl config use-context cka2-a`

One Helm release somewhere in the cluster is in the state `failed`. Find it and
uninstall it. The other releases must stay as they are.

---

## Question 5 | Never two on one node

Task weight: 5%

Use context: `kubectl config use-context cka2-b`

In Namespace `cka2-work`, create a Deployment `cache` with 2 replicas of `nginx:1.27`
(Pods labeled `app=cache`). Two of its Pods must never run on the same node, through
a required pod anti-affinity rule. They may run on the control plane node. Both
replicas must be ready.

---

## Question 6 | Pods that never fit

Task weight: 5%

Use context: `kubectl config use-context cka2-b`

In Namespace `cka2-work`, the Deployment `big` has no running Pods. Find out why, and
change its container's requests to `100m` CPU and `64Mi` memory, so that both
replicas run.

---

## Question 7 | A static Pod on node1

Task weight: 5%

Use context: `kubectl config use-context cka2-a`

Run a static Pod `node-probe` in Namespace `cka2-work` on `node1`: image
`busybox:1.36`, command `sleep infinity`, from the manifest
`/etc/kubernetes/manifests/node-probe.yaml` on `node1`.

---

## Question 8 | Route by header

Task weight: 6%

Use context: `kubectl config use-context cka2-a`

In Namespace `cka2-net`, the Gateway `cka2-gw` exists. Create an HTTPRoute
`version-route` attached to it for the host name `app.cka2.test`, with two rules:
requests with the header `X-Version: v2` go to the Service `app-v2` on port `80`; all
other requests go to the Service `app-v1` on port `80`.

---

## Question 9 | A Pod with its own DNS settings

Task weight: 5%

Use context: `kubectl config use-context cka2-a`

In Namespace `cka2-net`, create a Pod `dns-client` (image `busybox:1.36`, command
`sleep infinity`) that does not inherit the cluster's DNS settings. Its
`/etc/resolv.conf` must use the cluster DNS Service's IP as its only nameserver,
`cka2-net.svc.cluster.local` as its only search domain, and `ndots:2`.

---

## Question 10 | A Service for something outside the cluster

Task weight: 5%

Use context: `kubectl config use-context cka2-a`

In Namespace `cka2-net`, create a Service `legacy-db` on port `5432` without a
selector, and the EndpointSlice that sends it to `10.0.0.50:5432` (IPv4).

---

## Question 11 | Lock a Namespace down

Task weight: 4%

Use context: `kubectl config use-context cka2-a`

In Namespace `cka2-locked`, create a NetworkPolicy `default-deny` that denies all
incoming and outgoing traffic of every Pod. DNS lookups must still work, through a
second policy. For example, Pod `a` must still resolve `b.cka2-locked.svc.cluster.local`,
but not reach it.

---

## Question 12 | A claim for the right volume

Task weight: 5%

Use context: `kubectl config use-context cka2-a`

In Namespace `cka2-data`, create a PersistentVolumeClaim `reports` (storage class
`manual`, `1Gi`, `ReadWriteOnce`) that binds only to a PersistentVolume labeled
`tier=reports`. It must be Bound.

---

## Question 13 | Part of a volume, read-only

Task weight: 5%

Use context: `kubectl config use-context cka2-a`

In Namespace `cka2-data`, the claim `shared` holds a directory `logs`. Create a Pod
`reader` (image `busybox:1.36`, command `sleep infinity`) that mounts only that
directory of `shared`, read-only, at `/data`. It must be able to read
`/data/app.log`.

---

## Question 14 | node2 is NotReady

Task weight: 8%

Use context: `kubectl config use-context cka2-a`

The node `node2` is `NotReady`. Find the cause on the node and fix it, so that the
node is `Ready` with the kubelet's configuration file corrected.

---

## Question 15 | A kubeconfig that does not trust the server

Task weight: 6%

Use context: `kubectl config use-context cka2-a`

`kubectl --kubeconfig /tmp/kbook/cka2/15/ops.kubeconfig get pods` fails. Fix the
file, without changing the user's credentials in it, so that it works for the user
`ops` in Namespace `cka2-ops`.

---

## Question 16 | What the previous container said

Task weight: 5%

Use context: `kubectl config use-context cka2-a`

In Namespace `cka2-ops`, the Pod `cruncher` failed once and was restarted. Save the
line its previous container printed, and nothing else, to
`/tmp/kbook/cka2/16/line.txt`.

---

## Question 17 | A policy that blocks its own client

Task weight: 7%

Use context: `kubectl config use-context cka2-a`

In Namespace `cka2-net`, the NetworkPolicy `restrict` should let the Pod `client`
(label `role=client`) reach the Service `api`, but `client` times out. Fix the policy,
without deleting it, so that `client` reaches `api` and `outsider` still does not.

---

## Question 18 | The etcd member

Task weight: 4%

Use context: `kubectl config use-context cka2-a`

Write the name of the cluster's etcd member and its peer URL, separated by one space,
to `/tmp/kbook/cka2/18/etcd.txt`.
