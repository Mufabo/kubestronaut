# Mock exam: Part VI simulator

> **Exams:** CKNE (performance-based style)
> **Covers:** Chapters 48 to 52 (all of Part VI: Core Infrastructure and CNI)
> **Time:** 60 minutes · **Questions:** 8 · **Pass mark:** 67%
> **Lab tier:** 1 (kind, profile `nocni`, with Cilium and Multus installed by the setup)

This is a timed, scored simulator in the style of killer.sh: weighted
questions, scored all at once, harder and more hurried than the real exam. It
uses only what Chapters 48 to 52 teach. Do it after Chapter 52.

## How it works

```bash
make mock EXAM=part6          # build the exam (a new cluster, about 10 minutes); the clock starts when it is ready
make mock-score EXAM=part6    # score your answers, as often as you like
make mock-reset EXAM=part6    # start over from scratch (builds a new cluster)
make mock-teardown EXAM=part6 # remove the exam and its cluster
```

The setup builds its own cluster: Cilium in multi-pool IPAM mode with native
routing (default pool `10.10.0.0/16`), the CNI reference plugins, and Multus.

- **Context.** The exam creates the context `p6-a`. Each question starts with
  the command to switch to it; run it every time, as in the real exam.
- **Nodes.** Where a question needs a node, use `docker exec -it <node> bash`
  (the exam's equivalent is `ssh <node>`). The nodes are `kbook-control-plane`,
  `kbook-worker`, and `kbook-worker2`.
- **Answer files.** Answers that are files go under `/tmp/kbook/part6/<question>/`.
  The folders already exist.
- **Documentation.** Allowed: `kubectl explain`, `--help`, kubernetes.io/docs,
  and docs.cilium.io, as in the exam. Not allowed: this book's chapters and the
  solutions file, until you have scored.
- **Weights.** A question counts only when everything it asks for is right.

When you are done, run `make mock-score EXAM=part6`, then read
[`lab/solutions.md`](lab/solutions.md) for every question you missed.

> **Exam tip:** Questions 3 to 8 each have a symptom you can see in a minute
> (`kubectl get pods`, one `curl` or `dig`). Look at all of them first, then
> fix the cheapest ones.

---

## Question 1 | The node's CNI configuration

Task weight: 10%

Use context: `kubectl config use-context p6-a`

On node `kbook-worker2`, find the CNI configuration the container runtime
uses, and the configuration of the plugin that creates every Pod's `eth0`.

- `/tmp/kbook/part6/1/conf`: the full path of the configuration file the runtime uses
- `/tmp/kbook/part6/1/cluster-network`: the `type` of the (first) plugin in the cluster network's configuration file

## Question 2 | Where Pod addresses come from

Task weight: 8%

Use context: `kubectl config use-context p6-a`

- `/tmp/kbook/part6/2/cluster-cidr`: the cluster CIDR the controller manager divides into node ranges
- `/tmp/kbook/part6/2/ipam`: the IPAM mode Cilium uses
- `/tmp/kbook/part6/2/probe-pool`: the name of the pool Pod `probe` in Namespace `p6-core` got its address from

## Question 3 | A namespace without addresses

Task weight: 12%

Use context: `kubectl config use-context p6-a`

The Deployment `web` in Namespace `p6-red` has no running Pods. Make both
replicas run, with addresses from a new pool:

- A `CiliumPodIPPool` named after the pool the Namespace asks for, with the single CIDR `10.21.0.0/16` and a mask size of 27
- Both `web` Pods are running, with addresses from `10.21.0.0/16`

## Question 4 | Not enough addresses

Task weight: 12%

Use context: `kubectl config use-context p6-a`

Only some of the 36 replicas of the Deployment `worker` in Namespace
`p6-batch` run. Make all of them run without changing the Deployment or the
Namespace.

- Pool `small` still contains `10.31.0.0/27` and a mask size of 28, and all its ranges are inside `10.31.0.0/16`
- The Deployment `worker` has 36 ready replicas

## Question 5 | A second interface

Task weight: 16%

Use context: `kubectl config use-context p6-a`

Pod `collector` in Namespace `p6-fabric` is attached to the secondary network
`fabric` with the address `172.18.110.4`. Create a Pod that sends to it over
that network:

- Pod `sensor` in `p6-fabric`, image `nicolaka/netshoot:v0.14`, running `sleep infinity`, on node `kbook-worker2`
- Its `fabric` interface is named `fab0` and has the address `172.18.110.5/24`
- `sensor` can ping `172.18.110.4`

## Question 6 | cart refuses connections

Task weight: 10%

Use context: `kubectl config use-context p6-a`

The Deployment `cart` in Namespace `p6-shop` should answer `cart-ok` on TCP
port 9000, but other Pods are refused.

- Pod `probe` in `p6-core` gets `cart-ok` from the `cart` Pod's address on port 9000 (test with `nc -w 2 <address> 9000`)

## Question 7 | Traffic to one node is lost

Task weight: 18%

Use context: `kubectl config use-context p6-a`

Pod `probe` (on `kbook-worker`) cannot reach Pod `echo` (on `kbook-worker2`)
in Namespace `p6-core`. Find the cause and fix it, without changing Cilium's
configuration and without moving the Pods.

- `probe` gets `echo` from `http://<echo's Pod IP>:8080/hostname`
- Cilium still routes natively

## Question 8 | A Pod that cannot resolve names

Task weight: 14%

Use context: `kubectl config use-context p6-a`

Pod `lookup` in Namespace `p6-core` cannot resolve Service names.

- `lookup`, still on `kbook-worker`, resolves `echo.p6-core.svc.cluster.local` to the Service's ClusterIP
- `lookup` uses the cluster's DNS through the default DNS policy
