# Mock exam: CKS simulator

> **Exam:** CKS (performance-based style)
> **Covers:** every CKS domain, weighted as in the curriculum: Cluster Setup 15%, Cluster Hardening 15%, System Hardening 10%, Minimize Microservice Vulnerabilities 20%, Supply Chain Security 20%, Monitoring, Logging and Runtime Security 20%
> **Time:** 120 minutes · **Questions:** 15 · **Pass mark:** 67%
> **Lab tier:** 2 (the VMs, snapshot `cluster`)

This is the full CKS simulator, in the style of killer.sh. Like killer.sh, it is
meant to be **harder and more hurried than the real exam**. It draws on Part IV
(Chapters 29 to 36) and on the RBAC and NetworkPolicy chapters before it. Take it
in the last two weeks before your exam (Chapter 39's CKS plan), after you have
worked through every Part IV lab.

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
make mock EXAM=cks            # build the exam; the clock starts when it is ready
make mock-score EXAM=cks      # score your answers, as often as you like
make mock-teardown EXAM=cks   # remove the exam and restore your kubectl settings
```

Setup installs what the questions need (etcdctl on `cp1`, gVisor on both workers,
Falco on `node1`) and takes several minutes the first time. `make mock EXAM=cks`
again starts over until you have changed the API server's storage or logging
(questions 8 and 13); from then on, and for a cluster exactly as the snapshot left
it, restore the snapshot on the host.

The rules mirror the real exam environment:

- **Contexts.** The exam creates two contexts, `cks-a` and `cks-b`. Each question
  names the context to use. Run that command first, every time. `cks-b` has a
  default namespace (`cks-prod`); `cks-a` does not.
- **Nodes.** Work on `cp1`. Reach the workers with `ssh node1` and `ssh node2`,
  and use `sudo` where a task needs root, as on the exam's SSH hosts.
- **Files.** Files a question starts from, and answers that are files, are under
  `/tmp/kbook/cks/<question>/`. Write exactly the file the question names.
- **Documentation.** Allowed: `kubectl explain`, `--help`, `man`, and the
  documentation Chapter 38 lists for the CKS (kubernetes.io/docs and blog, and the
  documentation of the tools the exam uses, such as Falco and AppArmor). Not
  allowed: this book's chapters and the solutions file, until you have scored.
- **Weights.** Every question has a task weight. A question counts only when
  everything it asks for is right; then you earn its whole weight.
- **Time.** `make mock-score` shows the time used. It never stops you.

When you are done, run `make mock-score EXAM=cks`, then read
[`lab/solutions.md`](lab/solutions.md) for every question you missed.

> **Exam tip:** Three questions change the API server's manifest (4, 8, and 13). Make each change carefully, or plan them together: every restart takes a minute, and a typo leaves you without an API until you find it.

---

## Question 1 | Default deny, with one exception

Task weight: 8%

Use context: `kubectl config use-context cks-a`

The Namespace `cks-shop` runs the Pods `frontend`, `api`, and `other`; `api` and
`other` serve HTTP on port 8080. Create a NetworkPolicy `default-deny` that denies
all incoming traffic to every Pod in `cks-shop`, and a NetworkPolicy `api-allow`
that lets only the Pods labelled `app=frontend` reach the Pods labelled `app=api`,
on TCP port 8080.

---

## Question 2 | Genuine binaries

Task weight: 7%

Use context: `kubectl config use-context cks-a`

`/tmp/kbook/cks/2/` holds three copies of `kubeadm`: `kubeadm-a`, `kubeadm-b`, and
`kubeadm-c`. Some of them have been modified. Compare them with the official
`kubeadm` of Kubernetes v1.37.0 for linux/amd64, and delete every file that does
not match. Do not change the files that do.

---

## Question 3 | A ServiceAccount with too much power

Task weight: 8%

Use context: `kubectl config use-context cks-a`

The ServiceAccount `deployer` in `cks-ci` is bound to `cluster-admin` by the
ClusterRoleBinding `deployer-admin`. It only needs to manage Deployments in its
own Namespace. Delete the ClusterRoleBinding, and give `deployer` a Role `deployer`
in `cks-ci` with exactly the verbs `get`, `list`, `create`, and `update` on
Deployments, bound by a RoleBinding `deployer`. `deployer` may do nothing else.

---

## Question 4 | Kubelets may change only what is theirs

Task weight: 7%

Use context: `kubectl config use-context cks-a`

Someone turned off the admission plugin that limits what a kubelet may change on
its own Node object (for example, labels with the prefix
`node-restriction.kubernetes.io/`). Turn it back on in the API server on `cp1`. The
API server must run with it.

---

## Question 5 | AppArmor for a Deployment

Task weight: 5%

Use context: `kubectl config use-context cks-a`

On `node2`, the file `/etc/apparmor.d/cks-guard` holds an AppArmor profile that is
not loaded. Load it on `node2`, and make both Pods of the Deployment `writer` in
`cks-sys` run under it, in enforce mode. The Deployment's Pods already run on
`node2`; keep 2 ready replicas there.

---

## Question 6 | A seccomp profile

Task weight: 5%

Use context: `kubectl config use-context cks-a`

`/tmp/kbook/cks/6/trace.json` is a seccomp profile. Install it on `node1` so that
the kubelet finds it as `cks/trace.json`, and create a Pod `tracer` in `cks-sys`
(image `busybox:1.36`, command `sleep infinity`) on `node1` that runs under it
(type `Localhost`, `localhostProfile: cks/trace.json`). The Pod must be Running.

---

## Question 7 | Enforce restricted

Task weight: 6%

Use context: `kubectl config use-context cks-a`

Make the Namespace `cks-pci` enforce the Pod Security level `restricted`. The
Deployment `payments` there (image `busybox:1.36`, which runs as root by default)
must keep running with 2 ready replicas, and every Pod in the Namespace must
comply with `restricted`.

---

## Question 8 | Encrypt Secrets with secretbox

Task weight: 7%

Use context: `kubectl config use-context cks-a`

Make the API server encrypt Secrets in etcd with the `secretbox` provider and a
key named `cks-key`, configured in `/etc/kubernetes/enc/cks.yaml`. The Secret
`card-keys` in `cks-pci`, which exists already, must be stored encrypted, and
must still return its original value through the API.

---

## Question 9 | A sandbox for untrusted code

Task weight: 7%

Use context: `kubectl config use-context cks-a`

The workers have gVisor's `runsc` runtime configured in containerd. Create a
RuntimeClass `sandboxed` that uses it, and make the Deployment `untrusted` in
`cks-sbx` run its Pods in it. The Deployment must have 1 ready replica, running
on gVisor's kernel.

---

## Question 10 | No latest images

Task weight: 7%

Use context: `kubectl config use-context cks-b`

In the Namespace `cks-prod`, reject every Deployment (created or updated) with a
container image that has no tag, or the tag `latest`. Images with any other tag,
and images referred to by digest (`name@sha256:...`), must be allowed. Use a
ValidatingAdmissionPolicy `cks-no-latest` and a ValidatingAdmissionPolicyBinding
`cks-no-latest` with the action `Deny`. Other Namespaces are not affected.

---

## Question 11 | Pin an image by digest

Task weight: 6%

Use context: `kubectl config use-context cks-b`

The Deployment `cache` in `cks-prod` runs `nginx:1.27`. Change it to refer to the
same image by its digest (`nginx@sha256:...`), the digest its Pod runs now. It
must have 1 ready replica afterwards.

---

## Question 12 | Harden a Dockerfile

Task weight: 7%

Use context: `kubectl config use-context cks-a`

Fix `/tmp/kbook/cks/12/Dockerfile` in place:

- Its base image is `python:3.12-slim` (one `FROM` line, exactly `FROM python:3.12-slim`)
- It contains no `API_TOKEN`
- It creates a user `appuser` with `useradd` in a `RUN` instruction, and the last `USER` instruction is `USER appuser`
- Its last instruction stays `CMD ["python", "app.py"]`

You do not need to build the image.

---

## Question 13 | Audit what matters

Task weight: 7%

Use context: `kubectl config use-context cks-a`

Make the API server write an audit log to `/var/log/kubernetes/audit/cks.log`,
keeping rotated files for at most 5 days and at most 3 of them, with the policy
`/etc/kubernetes/audit/cks-policy.yaml`:

- Secrets, in every Namespace: level `Metadata`
- `create`, `update`, `patch`, and `delete` of Deployments in `cks-prod`: level `RequestResponse`
- Every other request: not logged
- No event for the `RequestReceived` stage (one event per request)

---

## Question 14 | Who reads /etc/sudoers?

Task weight: 6%

Use context: `kubectl config use-context cks-a`

Falco runs on `node1`. One of the Pods `reporter` and `indexer` in `cks-run`, and
`fetcher` and `mailer` in `cks-prod`, reads `/etc/sudoers`. Write its Namespace and
name as `<namespace>/<pod>` (for example `cks-run/reporter`) to
`/tmp/kbook/cks/14/culprit.txt`, then delete that Pod. Leave the other three
running.

---

## Question 15 | An immutable web server

Task weight: 7%

Use context: `kubectl config use-context cks-a`

The Deployment `site` in `cks-run` runs `httpd:2.4` with a writable root file
system. Make its container's root file system read-only, adding only `emptyDir`
volumes where the server must write. The Deployment must keep 2 ready replicas
with the image `httpd:2.4`.
