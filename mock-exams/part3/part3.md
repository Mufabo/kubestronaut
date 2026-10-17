# Mock exam: Part III simulator

> **Exams:** CKA (performance-based style)
> **Covers:** Chapters 17 to 28 (the exam-style finale of Part III)
> **Time:** 120 minutes · **Questions:** 16 · **Pass mark:** 66%
> **Lab tier:** 2 (VirtualBox VMs, `envs/vagrant`, snapshot `cluster-prev`)

This is a timed, scored simulator in the style of killer.sh. Like killer.sh, it is
meant to be **harder and more hurried than the real exam**. It uses only what
Chapters 17 to 28 teach, and it closes Part III: do it after Chapter 28.

Unlike the Part I and Part II simulators, this one runs on the Tier 2 VMs,
because a cluster administrator's work happens on the machines: upgrades,
backups, kubelets, and static Pods. It starts from the `cluster-prev`
snapshot, a kubeadm cluster at v1.34.12.

## How it works

On the host, restore the snapshot and open a shell on `cp1`:

```powershell
.\envs\vagrant\kbook-vm.ps1 restore cluster-prev      # Windows; ./envs/vagrant/kbook-vm.sh on Linux/macOS
.\envs\vagrant\kbook-vm.ps1 ssh
```

Then, on `cp1`:

```bash
cd /kbook
make mock EXAM=part3          # build the exam (a few minutes); the clock starts when it is ready
make mock-score EXAM=part3    # score your answers, as often as you like
make mock-teardown EXAM=part3 # remove the exam's objects and restore your kubectl settings
```

To start over, restore `cluster-prev` on the host again; `make mock-reset EXAM=part3`
prints that command. The upgrade in Question 4 cannot be undone in place.

The rules mirror the real exam environment:

- **Contexts.** The exam creates two contexts, `p3-a` and `p3-b`, on the VM
  cluster. Each question names the context to use. Run that command first, every
  time. `p3-b` has a default namespace (`p3-apps`) and `p3-a` does not.
- **Nodes.** You work on `cp1`. `ssh node1` and `ssh node2` reach the workers;
  use `sudo` for anything that needs root.
- **Namespaces.** Each question names its Namespace. Use exactly that one.
- **Answer files.** Answers that are files go under `/tmp/kbook/part3/<question>/`
  on `cp1`. The folders already exist; write exactly the file the question names.
- **Tools.** `etcdctl` and `etcdutl` are installed on `cp1`, as in Chapter 20.
- **Documentation.** Allowed: `kubectl explain`, `--help`, and kubernetes.io/docs
  in a browser, as in the exam. Not allowed: this book's chapters and the
  solutions file, until you have scored.
- **Weights.** Every question has a task weight. A question counts only when
  everything it asks for is right; then you earn its whole weight. Your score is
  the sum. Skipping a hard question to finish the easy ones is a valid strategy.
- **Time.** `make mock-score` shows the time used. It never stops you.

When you are done, run `make mock-score EXAM=part3`, then read
[`lab/solutions.md`](lab/solutions.md) for every question you missed.

> **Exam tip:** Read all sixteen questions first, and start the slow one early. The upgrade in Question 4 spends minutes waiting on downloads and restarts; read the next question while it runs.

---

## Question 1 | A Pod on the control plane node

Task weight: 6%

Use context: `kubectl config use-context p3-a`

In Namespace `p3-sched`, create a Pod `fast` running `nginx:1.27` that runs on the
control plane node `cp1`. Select the node with a `nodeSelector` on the label
`kubernetes.io/hostname`, and let the Pod tolerate the control plane's
`NoSchedule` taint. Do not set `nodeName`. The Pod must be Running.

---

## Question 2 | A static Pod

Task weight: 6%

Use context: `kubectl config use-context p3-a`

Create a static Pod `ops-monitor` in Namespace `p3-ops` on the node `cp1`. It runs
`busybox:1.36` with the command `sleep infinity`. The kubelet must run it, and
the cluster must show it as Running.

---

## Question 3 | A join command for a new worker

Task weight: 5%

Use context: `kubectl config use-context p3-a`

A new worker will join the cluster tomorrow. Write a complete, working
`kubeadm join` command for it, with a valid bootstrap token and the CA
certificate hash, to `/tmp/kbook/part3/3/join.sh`. Do not join any node.

---

## Question 4 | Upgrade the control plane

Task weight: 12%

Use context: `kubectl config use-context p3-a`

The cluster runs v1.34.12. Upgrade the control plane node `cp1` to exactly
`v1.35.0`:

- The control plane components (API server, controller manager, scheduler) run `v1.35.0`.
- On `cp1`, the `kubeadm`, `kubelet`, and `kubectl` packages are at `1.35.0` and held.
- `cp1` reports `v1.35.0` and is schedulable when you are done.

Leave `node1` and `node2` at their current version.

---

## Question 5 | A Deployment that does not start

Task weight: 6%

Use context: `kubectl config use-context p3-b`

The Deployment `report` in Namespace `p3-apps` has no available replica. Its team
meant to run `nginx:1.27`. Fix the Deployment so that one replica is available.

---

## Question 6 | Back up etcd

Task weight: 7%

Use context: `kubectl config use-context p3-a`

Save a snapshot of the cluster's etcd to `/tmp/kbook/part3/6/etcd.db`.

---

## Question 7 | Protect the database

Task weight: 8%

Use context: `kubectl config use-context p3-a`

In Namespace `p3-net`, the Pod `db` (label `app=db`) serves on port 80 behind the
Service `db`. Create a NetworkPolicy `db-allow` so that only Pods labelled
`app=api` in the same Namespace can reach `db`, on TCP port 80. The Pod `api` must
still reach `http://db`; the Pod `other` must not.

---

## Question 8 | The Service network

Task weight: 4%

Use context: `kubectl config use-context p3-a`

Write the IP range that the cluster assigns Service IPs from, in CIDR notation
and nothing else, to `/tmp/kbook/part3/8/service-cidr.txt`.

---

## Question 9 | A static PersistentVolume

Task weight: 7%

Use context: `kubectl config use-context p3-a`

Create a PersistentVolume `logs-pv`: capacity `1Gi`, access mode `ReadWriteOnce`,
reclaim policy `Retain`, storage class `manual`, and a `hostPath` volume at
`/srv/p3-logs`. In Namespace `p3-data`, create a PersistentVolumeClaim `logs`
that requests `500Mi` with access mode `ReadWriteOnce` and storage class
`manual`, so that it binds to `logs-pv`. Then create a Pod `writer` running
`busybox:1.36` with the command `sleep infinity` that mounts the claim at `/logs`.
The Pod must be Running.

---

## Question 10 | A ServiceAccount that deploys

Task weight: 7%

Use context: `kubectl config use-context p3-b`

In Namespace `p3-apps`, create a ServiceAccount `deployer`. Give it permission to
`get`, `list`, `create`, and `update` Deployments in `p3-apps`, and nothing else,
with a Role `deploy-manager` and a RoleBinding `deployer`.

---

## Question 11 | A user who reads nodes

Task weight: 5%

Use context: `kubectl config use-context p3-a`

The user `auditor` must be able to get and list the cluster's nodes, and nothing
more. Create a ClusterRole `node-reader` and a ClusterRoleBinding
`auditor-nodes` for that.

---

## Question 12 | A custom resource

Task weight: 5%

Use context: `kubectl config use-context p3-a`

The cluster has a CustomResourceDefinition for `Backup` objects. In Namespace
`p3-ops`, create a Backup `nightly` with the schedule `0 2 * * *` and a
retention of `7`. Find the field names from the API.

---

## Question 13 | Scale with the load

Task weight: 5%

Use context: `kubectl config use-context p3-b`

In Namespace `p3-apps`, create a HorizontalPodAutoscaler `web` for the Deployment
`web`: between 2 and 5 replicas, at a target of 60% average CPU utilization.

---

## Question 14 | The shop does not answer

Task weight: 6%

Use context: `kubectl config use-context p3-b`

In Namespace `p3-apps`, requests to the Service `shop` on port 80 get no answer,
although the Deployment `shop` runs. Fix it, so that `http://shop` serves the
nginx welcome page from inside the Namespace. Keep the Service's port at 80.

---

## Question 15 | node2 is down

Task weight: 7%

Use context: `kubectl config use-context p3-a`

The node `node2` is `NotReady`. Find the cause on the node and fix it, so that the
node is Ready and stays that way after a reboot.

---

## Question 16 | The etcd CA

Task weight: 4%

Use context: `kubectl config use-context p3-a`

Write the date when the CA certificate of the cluster's etcd expires, exactly as
`openssl` prints the `notAfter` date (for example `Oct  9 17:43:57 2036 GMT`), to
`/tmp/kbook/part3/16/etcd-ca-expiry.txt`.
