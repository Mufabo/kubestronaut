# Mock exam: CKA simulator

> **Exam:** CKA (performance-based style)
> **Covers:** every CKA domain, weighted as in the curriculum: Cluster Architecture, Installation and Configuration 25%, Workloads and Scheduling 15%, Services and Networking 20%, Storage 10%, Troubleshooting 30%
> **Time:** 120 minutes · **Questions:** 18 · **Pass mark:** 66%
> **Lab tier:** 2 (the VMs, snapshot `cluster`)

This is the full CKA simulator, in the style of killer.sh. Like killer.sh, it is
meant to be **harder and more hurried than the real exam**. It covers all of the
CKA and does not repeat the Part III mock: take that one first, then this one in
the last two weeks before your exam (Chapter 39's CKA plan).

## How it works

The exam runs on `cp1` of the Tier 2 VMs, from the `cluster` snapshot (every node
at the book's Kubernetes version). On the host:

```bash
make cluster-pause                       # in WSL, if the kind cluster runs: frees RAM
envs/vagrant/kbook-vm restore cluster    # Windows: .\envs\vagrant\kbook-vm.ps1 restore cluster
envs/vagrant/kbook-vm ssh                # a shell on cp1
```

Then, on `cp1`:

```bash
cd /kbook
make mock EXAM=cka            # build the exam; the clock starts when it is ready
make mock-score EXAM=cka      # score your answers, as often as you like
make mock-teardown EXAM=cka   # remove the exam and restore your kubectl settings
```

Setup installs what the questions need (Helm, metrics-server, the Gateway API
CRDs) and takes a few minutes. `make mock EXAM=cka` again starts over; for a
cluster exactly as the snapshot left it, restore the snapshot on the host.

The rules mirror the real exam environment:

- **Contexts.** The exam creates two contexts, `cka-a` and `cka-b`. Each question
  names the context to use. Run that command first, every time. `cka-b` has a
  default namespace (`cka-work`); `cka-a` does not.
- **Nodes.** Work on `cp1`. Reach the workers with `ssh node1` and `ssh node2`,
  and use `sudo` where a task needs root, as on the exam's SSH hosts.
- **Files.** Files a question starts from, and answers that are files, are under
  `/tmp/kbook/cka/<question>/`. Write exactly the file the question names.
- **Documentation.** Allowed: `kubectl explain`, `--help`, `man`, and the
  documentation Chapter 38 lists for the CKA (kubernetes.io/docs and blog,
  helm.sh/docs, gateway-api.sigs.k8s.io). Not allowed: this book's chapters and
  the solutions file, until you have scored.
- **Weights.** Every question has a task weight. A question counts only when
  everything it asks for is right; then you earn its whole weight.
- **Time.** `make mock-score` shows the time used. It never stops you.

When you are done, run `make mock-score EXAM=cka`, then read
[`lab/solutions.md`](lab/solutions.md) for every question you missed.

> **Exam tip:** Read all the questions first and start with the troubleshooting
> ones that block nothing else for you. A broken node or component can take a long
> time; note it and come back if it does not give way in ten minutes.

---

## Question 1 | A user certificate

Task weight: 8%

Use context: `kubectl config use-context cka-a`

The user `jane` has a private key and a certificate signing request in
`/tmp/kbook/cka/1/` (`jane.key`, `jane.csr`). Create a CertificateSigningRequest
named `jane` for the cluster's client signer
(`kubernetes.io/kube-apiserver-client`), approve it, and save the issued
certificate to `/tmp/kbook/cka/1/jane.crt`. Then create a Role `pod-reader` in
Namespace `cka-team` that allows `get`, `list`, and `watch` on Pods, and bind it to
the user `jane` with a RoleBinding `jane-pods`. `jane` may do nothing else.

---

## Question 2 | Install a component with Helm

Task weight: 6%

Use context: `kubectl config use-context cka-a`

The chart in `/tmp/kbook/cka/2/chart` installs a small web component. Write a values
file `/tmp/kbook/cka/2/values.yaml` that sets `replicaCount` to `2` and the
Service type (`service.type`) to `NodePort`. Install the chart with it as the
release `edge` in a new Namespace `cka-infra`. The release must be `deployed`, with
2 ready replicas.

---

## Question 3 | Renew the API server certificate

Task weight: 7%

Use context: `kubectl config use-context cka-a`

Renew the certificate the API server uses for serving (only that one) with kubeadm
on `cp1`. The API server must serve the renewed certificate when you are done.

---

## Question 4 | Extension interfaces

Task weight: 4%

Use context: `kubectl config use-context cka-a`

Write two lines to `/tmp/kbook/cka/4/interfaces.txt`:

1. the container runtime endpoint the kubelet on `node1` is configured with, exactly
   as its configuration file states it;
2. the name of the CNI configuration file that `node1` uses, from
   `/etc/cni/net.d` (the file name only).

---

## Question 5 | Place a workload by node label and priority

Task weight: 6%

Use context: `kubectl config use-context cka-b`

Create a PriorityClass `cka-high` with the value `100000`. Label the node `node2`
with `tier=compute`. In Namespace `cka-work`, create a Deployment `analytics`
(image `nginx:1.27`, 2 replicas, Pods labeled `app=analytics`) whose Pods use
`cka-high` and may only run on nodes where `tier` is `compute`, through a required
node affinity rule with the operator `In`. Both replicas must be ready.

---

## Question 6 | Autoscale a Deployment

Task weight: 4%

Use context: `kubectl config use-context cka-b`

In Namespace `cka-work`, create a HorizontalPodAutoscaler `api` for the Deployment
`api`: between 2 and 6 replicas, at an average CPU utilization of 50%. When it
scales down, it must wait for a stabilization window of 60 seconds.

---

## Question 7 | Roll back to the first image

Task weight: 5%

Use context: `kubectl config use-context cka-b`

In Namespace `cka-work`, the Deployment `portal` has been updated twice. Roll it
back to the revision that ran `nginx:1.25`. The rollout must finish with 2 ready
replicas and no old Pods.

---

## Question 8 | Route traffic with the Gateway API

Task weight: 6%

Use context: `kubectl config use-context cka-a`

In Namespace `cka-net`, the Gateway `cka-gw` exists. Create an HTTPRoute
`api-route` attached to it for the host name `api.cka.test`. Requests whose path
starts with `/v1` (path match type `PathPrefix`) go to the Service `api` on port
`8080` with weight 90, and to the Service `api-v2` on port `8080` with weight 10.

---

## Question 9 | Ingress from a partner Namespace

Task weight: 6%

Use context: `kubectl config use-context cka-a`

In Namespace `cka-net`, the Pods labeled `app=backend` serve on port 80. Create a
NetworkPolicy `backend-ingress` so that they accept connections only from Pods that
are labeled `role=client` **and** run in a Namespace labeled `purpose=partners`, and
only on TCP port 80. (The Namespace `cka-team` has that label.)

---

## Question 10 | A NodePort Service

Task weight: 4%

Use context: `kubectl config use-context cka-a`

In Namespace `cka-net`, create a Service `legacy-np` of type NodePort for the Pods of
the Deployment `legacy`: port `80` to the container's port `80`, on node port
`30080`. `curl http://192.168.56.10:30080` on `cp1` must return the nginx page.

---

## Question 11 | A name in CoreDNS

Task weight: 4%

Use context: `kubectl config use-context cka-a`

Configure the cluster's CoreDNS so that every Pod resolves the name
`shop.cka.local` to the cluster IP of the Service `legacy` in Namespace `cka-net`.
All other names must resolve as before.

---

## Question 12 | A local volume, bound when used

Task weight: 7%

Use context: `kubectl config use-context cka-a`

- Create a StorageClass `local-wait` with the provisioner
  `kubernetes.io/no-provisioner`, the volume binding mode `WaitForFirstConsumer`,
  and the reclaim policy `Retain`.
- Create a PersistentVolume `fast-pv` of class `local-wait`: `1Gi`, access mode
  `ReadWriteOnce`, a `local` volume at `/srv/cka-fast` on `node2` (the directory
  exists).
- In Namespace `cka-data`, create a PersistentVolumeClaim `fast` of class
  `local-wait` for `500Mi`, and a Pod `fast-writer` (image `busybox:1.36`) that
  mounts it at `/data`, writes `ok` to `/data/ok`, and keeps running.

The claim must be bound to `fast-pv`, and the Pod Running.

---

## Question 13 | Keep the data

Task weight: 3%

Use context: `kubectl config use-context cka-a`

The PersistentVolume `archive-pv` would be deleted together with its claim. Change it
so that it is kept. Then create a PersistentVolumeClaim `archive` in Namespace
`cka-data` (storage class `manual`, `1Gi`, `ReadWriteOnce`) that binds to it.

---

## Question 14 | node1 is NotReady

Task weight: 7%

Use context: `kubectl config use-context cka-a`

The node `node1` is `NotReady`. Find the cause on the node and fix it, so that the
node is `Ready` and stays so after a reboot.

---

## Question 15 | A second scheduler that does not run

Task weight: 7%

Use context: `kubectl config use-context cka-a`

A second scheduler, `cka-scheduler`, runs as a static Pod on `cp1` in Namespace
`cka-ops`, but it keeps failing, and the Pod `waiting`, which asks for it, is never
scheduled. Fix the scheduler. Do not change the Pod `waiting`. The scheduler's Pod
must be Running, and `waiting` must be Running.

---

## Question 16 | Who uses the memory?

Task weight: 5%

Use context: `kubectl config use-context cka-a`

In Namespace `cka-ops`, three Pods are labeled `app=meter`. Write the name of the one
that uses the most memory, and nothing else, to `/tmp/kbook/cka/16/pod.txt`.

---

## Question 17 | Out of a locked-down Namespace

Task weight: 6%

Use context: `kubectl config use-context cka-a`

In Namespace `cka-ops`, the NetworkPolicy `lockdown` blocks all outgoing traffic.
The Pod `client` (label `app=client`) must reach the Service `web` in Namespace
`cka-net` by name (`wget -qO- http://web.cka-net`). Allow exactly that, plus the DNS
lookups it needs: `client` must not reach any other Pod in `cka-net`. Do not change
`lockdown`.

---

## Question 18 | A Pod that no node accepts

Task weight: 5%

Use context: `kubectl config use-context cka-a`

In Namespace `cka-ops`, the Deployment `infra-agent` never starts its Pod. Make it
run on `node2`, without changing the Deployment, so that `node2` is the only node
that would accept it.
