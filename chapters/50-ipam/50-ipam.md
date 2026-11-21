# Chapter 50: IPAM and Pod CIDR allocation

> **Exams:** CKNE · D1 Core Infrastructure and CNI (Managing IPAM and Pod CIDR Allocation)
> **Difficulty:** Intermediate
> **Time:** ~60 min reading, ~45 min lab
> **Lab tier:** 1 (kind, profile `nocni`)
> **Prerequisites:** Chapter 40 (subnetting), Chapter 48 (`podCIDR` and `host-local`), Chapter 49 (installing Cilium)

## Learning objectives

After this chapter you can:

- Find the ranges Kubernetes itself allocates: the cluster CIDR, each node's `podCIDR`, and the mask size between them
- Size a Pod range: how many nodes and how many Pods per node a CIDR allows
- Compare IPAM modes: Kubernetes host-scope, Cilium cluster-pool and multi-pool, and Calico IP pools
- Give a namespace or a single Pod addresses from a pool of your choice with Cilium multi-pool IPAM
- Recognize a Pod that cannot get an address, and fix an exhausted pool without disturbing running Pods

## Concepts

### Who hands out Pod addresses

Chapter 48 introduced **IPAM** (IP address management): the part of a CNI plugin
that picks an address for each new Pod and makes sure no two Pods get the same
one. There, the `host-local` plugin did it, from a range written into each
node's configuration. Real clusters have more moving parts, and two layers can
each claim the job.

The first layer is Kubernetes. When the controller manager runs with
`--allocate-node-cidrs=true`, it carves the **cluster CIDR**
(`--cluster-cidr`) into one block per node and writes each block into the
Node object as `spec.podCIDR`. The size of those blocks is the **node CIDR mask
size** (`--node-cidr-mask-size`, default `/24` for IPv4 and `/64` for IPv6).
Kubernetes never assigns an address to a Pod; it only offers each node a range.

The second layer is the CNI plugin. It may use the node's `podCIDR`, as
`host-local` did and as Cilium does with `ipam.mode=kubernetes` (Chapter 49).
It may also ignore it completely and run its own scheme. Both are common, and
both are correct, as long as you know which one a cluster uses. The
`podCIDR` in the Node object then says nothing about where Pod addresses
really come from.

> **Why this matters for Kubernetes:** "which range does this Pod's address
> come from?" has two possible answers. Compare `kubectl get pods -o wide` with
> `kubectl get node -o jsonpath='{.spec.podCIDR}'` before you trust either.

### Sizing a Pod range

The mask sizes decide two limits at once. With a cluster CIDR of `/16` and a
node mask of `/24`, there are 2^(24-16) = 256 node blocks, so at most 256 nodes,
and each block has 2^(32-24) = 256 addresses. Subtract the network and
broadcast addresses and one or two the plugin keeps for itself (Cilium uses
one per node for its `cilium_host` interface, and one for health checks), and
about 250 Pods fit on a node.

The kubelet has its own limit, `maxPods`, 110 by default, which is why a `/24`
per node is the usual choice: it leaves room for twice the default. A `/25`
(128 addresses) also fits 110 Pods, and doubles the number of nodes the cluster
CIDR can hold. The trade-off is always the same: a larger node block means fewer
nodes, a smaller one fewer Pods per node.

Three ranges must never overlap: the Pod range, the Service range
(`--service-cluster-ip-range`, Chapter 53), and the network the nodes sit on.
A fourth joins them when clusters talk to each other (Chapter 62): two clusters
with the same Pod range cannot route to each other's Pods.

### IPAM modes

| Mode | Who decides the per-node range | Pool | Grows on demand | Typical use |
| --- | --- | --- | --- | --- |
| Kubernetes host-scope (`host-local`, Cilium `kubernetes`, Flannel) | the controller manager (`podCIDR`) | the cluster CIDR | no: one block per node, fixed | simple clusters, kubeadm defaults |
| Cilium **cluster-pool** (the chart's default) | the Cilium operator | Cilium's own list (`10.0.0.0/8`) | no: one block per node | clusters that want Cilium to own IPAM |
| Cilium **multi-pool** | the Cilium operator, per pool | several `CiliumPodIPPool` objects | yes: more blocks when a node needs them | different ranges per team or workload, growing a full pool |
| Calico IP pools | Calico (blocks per node) | `IPPool` objects, `192.168.0.0/16` by default | yes: more blocks, or borrowed addresses | Calico clusters |
| Cloud IPAM (AWS ENI, Azure, GKE) | the cloud provider | the VPC's subnets | depends on the provider | managed Kubernetes |

In cluster-pool mode, the Cilium operator gives each node one block from its
list and records it in the node's **CiliumNode** object (one per node, the
Cilium agent's view of its node). Changing the list later only affects nodes
that join afterwards.

Calico works with **IP pools** (`IPPool` resources) cut into **blocks**,
`/26` (64 addresses) by default. A node claims a block when it needs addresses
and claims another when the first is full, and when the pool has no free
block left it borrows single addresses from other nodes' blocks. You met
Calico's default pool in Parts I to IV: the `calico` profile's Pods have
addresses from `192.168.0.0/16`.

### Cilium multi-pool IPAM

**Multi-pool IPAM** (`ipam.mode=multi-pool`) lets a cluster have several
address pools and hand out blocks from them on demand. A pool is a
**CiliumPodIPPool** object (API version `cilium.io/v2alpha1`) with a list of
CIDRs and a block size:

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumPodIPPool
metadata:
  name: blue
spec:
  ipv4:
    cidrs: ["10.20.0.0/16"]
    maskSize: 28      # each node gets /28 blocks (16 addresses) from this pool
```

A Pod's pool is chosen by the annotation `ipam.cilium.io/ip-pool`: on the Pod
itself, or on its namespace, and otherwise the pool named `default`. When a
node needs an address from a pool it has no free address in, its agent asks for
another block, and the operator records the new block in the node's CiliumNode
object under `spec.ipam.pools.allocated`. Blocks are allocated as the load
arrives, so two nodes can end up with very different shares of a pool.

By default the first and last address of every block are not used
(`allowFirstIP` and `allowLastIP` are `false`), so a `/28` holds 14 Pods, not
16. Multi-pool also works best with native routing (Chapter 49): every block
gets its own route on every node, pointing at the node that owns it.

### Running out of addresses

A Pod that gets no address never starts. The scheduler did its job, so the
Pod is assigned to a node, but it stays in `ContainerCreating`, and its events
show `FailedCreatePodSandBox` with the CNI plugin's error, for example `all
CIDR ranges are exhausted` or, in host-scope modes, a full range. Nothing in
the Pod's own spec is wrong, which makes this failure easy to misread.

How you fix it depends on the mode:

- **Host-scope** (one `podCIDR` per node): a node's block cannot grow. Add
  nodes, or rebuild with a smaller node mask or a larger cluster CIDR. That is
  why sizing comes first.
- **Cilium cluster-pool:** the same; existing nodes keep their block.
- **Cilium multi-pool and Calico:** add a CIDR to the pool. Existing Pods keep
  their addresses, and waiting Pods start as soon as their nodes can claim a
  block from the new range. Removing a range that Pods still use is not safe.

The same `ContainerCreating` symptom appears when a namespace asks for a pool
that does not exist: the agent reports `pool not (yet) available` and keeps
retrying, so creating the pool is enough.

### Packet walk: a new Pod's first packet

A Pod `api` in a namespace annotated `ipam.cilium.io/ip-pool: blue` starts on
`kbook-worker`, which has no block from `blue` yet. Its first packet goes to a
Pod on `kbook-worker2`.

```mermaid
sequenceDiagram
    participant K as kubelet and runtime (kbook-worker)
    participant A as cilium agent (kbook-worker)
    participant O as cilium operator
    participant W2 as kbook-worker2
    K->>A: cilium-cni ADD: an address for api, pool blue
    A->>O: CiliumNode: needs addresses from pool blue
    O->>A: allocated 10.20.0.0/28 to kbook-worker
    A->>K: api gets 10.20.0.1; route 10.20.0.0/28 via cilium_host
    Note over A,W2: kbook-worker2 learns the new block and adds 10.20.0.0/28 via 172.18.0.2
    K->>W2: first packet 10.20.0.1 to a Pod there, routed natively via eth0
```

*Text description: the runtime on kbook-worker runs cilium-cni for the new Pod api; the agent has no free address in pool blue, so it records the need in its CiliumNode object; the operator allocates the block 10.20.0.0/28 to kbook-worker; the agent gives api the address 10.20.0.1 and routes the block locally through cilium_host. kbook-worker2 learns about the block and routes 10.20.0.0/28 via kbook-worker's address, so api's first packet to a Pod on kbook-worker2 goes out on eth0 with its Pod address, and replies find their way back.*

## Guided walkthrough

The walkthrough builds two `nocni` clusters: one with Cilium's default
cluster-pool IPAM, then one with multi-pool. Your block assignments will
differ; the shapes will not.

### Step 1: What Kubernetes allocates

```bash
make cluster PROFILE=nocni
docker exec kbook-control-plane grep -E 'cluster-cidr|node-cidr-mask|allocate-node-cidrs|service-cluster-ip-range' \
  /etc/kubernetes/manifests/kube-controller-manager.yaml
```

```text
    - --allocate-node-cidrs=true
    - --cluster-cidr=10.244.0.0/16
    - --service-cluster-ip-range=10.96.0.0/16
```

No `--node-cidr-mask-size` flag, so the default `/24` applies: 256 blocks of
256 addresses in `10.244.0.0/16`. On the exam's kubeadm clusters, the same
flags are in the same file on the control plane node.

### Step 2: Cilium's default, cluster-pool

Install Cilium with no IPAM setting at all:

```bash
helm install cilium cilium --repo https://helm.cilium.io --version 1.20.5 -n kube-system
cilium status --wait
cilium config view | grep -E '^(ipam|cluster-pool-ipv4-cidr|cluster-pool-ipv4-mask-size) '
```

```text
cluster-pool-ipv4-cidr                            10.0.0.0/8
cluster-pool-ipv4-mask-size                       24
ipam                                              cluster-pool
```

Compare the blocks Cilium chose with the ones Kubernetes assigned:

```bash
kubectl get ciliumnodes -o custom-columns=NAME:.metadata.name,PODCIDRS:.spec.ipam.podCIDRs
kubectl get nodes -o custom-columns=NAME:.metadata.name,PODCIDR:.spec.podCIDR
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
```

```text
NAME                  PODCIDRS
kbook-control-plane   [10.0.1.0/24]
kbook-worker          [10.0.2.0/24]
kbook-worker2         [10.0.0.0/24]
```

```text
NAME                  PODCIDR
kbook-control-plane   10.244.0.0/24
kbook-worker          10.244.2.0/24
kbook-worker2         10.244.1.0/24
```

```text
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE            NOMINATED NODE   READINESS GATES
coredns-559f6c778d-9kpck   0/1     Running   0          4m    10.0.0.123   kbook-worker2   <none>           <none>
coredns-559f6c778d-cwxc2   1/1     Running   0          4m    10.0.0.34    kbook-worker2   <none>           <none>
```

Two complete sets of node blocks. CoreDNS on `kbook-worker2` has addresses from
`10.0.0.0/24`, Cilium's block, while the Node object still claims
`10.244.1.0/24`. Nothing is broken: Cilium routes its own blocks. But a tool or
a person that trusts `spec.podCIDR` is misled.

### Step 3: Multi-pool, and a setting it cannot do without

Start again with a fresh cluster and install Cilium in multi-pool mode, with a
`default` pool of `10.10.0.0/16` in `/27` blocks and native routing:

```bash
make cluster-fresh PROFILE=nocni
helm install cilium cilium --repo https://helm.cilium.io --version 1.20.5 -n kube-system \
  --set ipam.mode=multi-pool \
  --set 'ipam.operator.autoCreateCiliumPodIPPools.default.ipv4.cidrs={10.10.0.0/16}' \
  --set ipam.operator.autoCreateCiliumPodIPPools.default.ipv4.maskSize=27 \
  --set routingMode=native --set autoDirectNodeRoutes=true --set ipv4NativeRoutingCIDR=10.0.0.0/8
kubectl -n kube-system get pods -l k8s-app=cilium
```

The agents never become ready; they restart over and over. Their log ends with
the reason:

```bash
kubectl -n kube-system logs <cilium-pod> -c cilium-agent --previous | grep panic
```

```text
panic: Egress masquerading interfaces cannot be empty when IP masquerading is enabled with IPAM mode other than ClusterPool or Kubernetes
```

In multi-pool mode, Cilium cannot work out which traffic leaves the cluster
from a single Pod range, so it needs to be told which interfaces lead out
(Chapter 41's masquerading, done by Cilium). On the kind nodes that is `eth0`:

```bash
helm upgrade cilium cilium --repo https://helm.cilium.io --version 1.20.5 -n kube-system \
  --reuse-values --set egressMasqueradeInterfaces=eth0
kubectl -n kube-system rollout restart daemonset/cilium
kubectl -n kube-system rollout status daemonset/cilium
kubectl get ciliumpodippools
kubectl get ciliumnodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.ipam.pools}{"\n"}{end}'
```

```text
NAME      AGE
default   32s
```

```text
kbook-control-plane {"allocated":[{"cidrs":["10.10.0.32/27"],"pool":"default"}],"requested":[{"needed":{"ipv4-addrs":8},"pool":"default"}]}
kbook-worker {"allocated":[{"cidrs":["10.10.0.0/27"],"pool":"default"}],"requested":[{"needed":{"ipv4-addrs":8},"pool":"default"}]}
kbook-worker2 {"allocated":[{"cidrs":["10.10.0.64/27"],"pool":"default"}],"requested":[{"needed":{"ipv4-addrs":8},"pool":"default"}]}
```

The operator created the `default` pool from the Helm values and gave each node
one `/27` block. `requested` is what each agent asked for: a few spare
addresses, so the next Pods start without waiting.

### Step 4: A pool for one namespace

Annotate a namespace with a pool that does not exist yet, and start a
Deployment in it:

```bash
kubectl create namespace green
kubectl annotate namespace green ipam.cilium.io/ip-pool=green
kubectl -n green create deployment web --image=registry.k8s.io/e2e-test-images/agnhost:2.66.1 \
  --replicas=2 -- /agnhost netexec --http-port=8080
kubectl -n green get pods
kubectl -n green describe pod <a-web-pod> | grep FailedCreatePodSandBox
```

```text
NAME                   READY   STATUS              RESTARTS   AGE
web-6fb755dd8f-fnn8t   0/1     ContainerCreating   0          77s
web-6fb755dd8f-rk7qm   0/1     ContainerCreating   0          77s
```

```text
plugin type="cilium-cni" failed (add): unable to allocate IP via local cilium agent: [POST /ipam][502] postIpamFailure "unable to allocate from pool \"green\" (family ipv4): pool not (yet) available"
```

Scheduled, but no address: the pool is missing. Create a pool for a second
namespace, `blue`, before its Pods start:

```bash
kubectl apply -f - <<'EOF'
apiVersion: cilium.io/v2alpha1
kind: CiliumPodIPPool
metadata:
  name: blue
spec:
  ipv4:
    cidrs: ["10.20.0.0/16"]
    maskSize: 28
EOF
kubectl create namespace blue
kubectl annotate namespace blue ipam.cilium.io/ip-pool=blue
kubectl -n blue create deployment api --image=registry.k8s.io/e2e-test-images/agnhost:2.66.1 \
  --replicas=3 -- /agnhost netexec --http-port=8080
kubectl -n blue get pods -o wide
```

```text
NAME                  READY   STATUS    RESTARTS   AGE     IP           NODE            NOMINATED NODE   READINESS GATES
api-9f544748c-47xg8   1/1     Running   0          6m16s   10.20.0.1    kbook-worker    <none>           <none>
api-9f544748c-dx7lx   1/1     Running   0          6m16s   10.20.0.24   kbook-worker2   <none>           <none>
api-9f544748c-w5xzq   1/1     Running   0          6m16s   10.20.0.4    kbook-worker    <none>           <none>
```

Every `api` Pod has an address from `10.20.0.0/16`. `kbook-worker` got the
block `10.20.0.0/28` and `kbook-worker2` the next one, `10.20.0.16/28`. Look
at the routes on a node:

```bash
docker exec kbook-worker ip route | grep -E '10\.(10|20)\.'
```

```text
10.10.0.0/27 via 10.10.0.29 dev cilium_host proto kernel src 10.10.0.29
10.10.0.29 dev cilium_host proto kernel scope link
10.10.0.32/27 via 172.18.0.3 dev eth0 proto kernel
10.10.0.64/27 via 172.18.0.4 dev eth0 proto kernel
10.20.0.0/28 via 10.10.0.29 dev cilium_host proto kernel src 10.10.0.29
10.20.0.16/28 via 172.18.0.4 dev eth0 proto kernel
```

One route per block: the node's own blocks go to `cilium_host`, every other
block to the node that owns it. A Pod on the default pool reaches a Pod in
`blue` like any other:

```bash
kubectl run probe --image=nicolaka/netshoot:v0.14 \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"kbook-worker"}}}' -- sleep infinity
kubectl get pod probe -o jsonpath='{.status.podIP}{"\n"}'
kubectl exec probe -- curl -s http://10.20.0.24:8080/clientip
```

```text
10.10.0.25
10.10.0.25:55754
```

A single Pod can pick a pool too, with the same annotation on the Pod:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: metrics
  annotations: {ipam.cilium.io/ip-pool: blue}
spec:
  containers: [{name: m, image: "registry.k8s.io/e2e-test-images/agnhost:2.66.1", args: ["netexec", "--http-port=8080"]}]
EOF
kubectl get pod metrics -o jsonpath='{.status.podIP} {.spec.nodeName}{"\n"}'
```

```text
10.20.0.21 kbook-worker2
```

### Step 5: Run a pool dry, and grow it

A pool `small` of `10.30.0.0/27` with `/28` blocks has room for two blocks of
14 usable addresses. Ask it for 40 Pods:

```bash
kubectl apply -f - <<'EOF'
apiVersion: cilium.io/v2alpha1
kind: CiliumPodIPPool
metadata:
  name: small
spec:
  ipv4:
    cidrs: ["10.30.0.0/27"]
    maskSize: 28
EOF
kubectl create namespace batch
kubectl annotate namespace batch ipam.cilium.io/ip-pool=small
kubectl -n batch create deployment batch --image=registry.k8s.io/e2e-test-images/agnhost:2.66.1 \
  --replicas=40 -- /agnhost pause
```

28 Pods start, 14 per block, and 12 stay in `ContainerCreating`. Their events
name the reason:

```text
plugin type="cilium-cni" failed (add): unable to allocate IP via local cilium agent: [POST /ipam][502] postIpamFailure "all CIDR ranges are exhausted"
```

How the blocks are shared depends on which node asks first. In a second run,
with a pool `tiny` of the same size, one node took both blocks, and the other
node's Pods got nothing at all:

```text
NAME    READY   UP-TO-DATE   AVAILABLE   AGE
batch   20/40   40           20          101s
```

```text
"cidrs":["10.40.0.0/28","10.40.0.16/28"],"pool":"tiny"
```

```text
     20 ContainerCreating kbook-worker
     20 Running kbook-worker2
```

The first line is the `tiny` entry of `kbook-worker2`'s allocations; the
counts come from `kubectl -n tiny get pods -o wide`, grouped by status and node.

The fix is the same in both cases: give the pool another range. Running Pods
keep their addresses.

```bash
kubectl patch ciliumpodippool small --type=merge \
  -p '{"spec":{"ipv4":{"cidrs":["10.30.0.0/27","10.30.1.0/26"]}}}'
kubectl -n batch get deployment batch
kubectl get ciliumnode kbook-worker -o jsonpath='{.spec.ipam.pools}' | python3 -m json.tool
```

```text
ciliumpodippool.cilium.io/small patched
```

```text
NAME    READY   UP-TO-DATE   AVAILABLE   AGE
batch   40/40   40           40          114s
```

```text
{
    "allocated": [
        {
            "cidrs": [
                "10.20.0.0/28"
            ],
            "pool": "blue"
        },
        {
            "cidrs": [
                "10.10.0.0/27"
            ],
            "pool": "default"
        },
        {
            "cidrs": [
                "10.30.0.16/28",
                "10.30.1.0/28"
            ],
            "pool": "small"
        }
    ],
    "requested": [
        {
            "needed": {
                "ipv4-addrs": 2
            },
            "pool": "blue"
        },
        {
            "needed": {
                "ipv4-addrs": 16
            },
            "pool": "default"
        },
        {
            "needed": {
                "ipv4-addrs": 20
            },
            "pool": "small"
        }
    ]
}
```

`kbook-worker` now holds one block from each range of `small`. Clean up with
`make cluster` (back to the default profile).

### Useful commands from this chapter

| Command | What it tells you |
| --- | --- |
| `grep cidr /etc/kubernetes/manifests/kube-controller-manager.yaml` (on the control plane) | the cluster CIDR and the node mask size Kubernetes uses |
| `kubectl get nodes -o custom-columns=NAME:.metadata.name,PODCIDR:.spec.podCIDR` | the range Kubernetes offered each node |
| `cilium config view \| grep ipam` | the IPAM mode Cilium really uses |
| `kubectl get ciliumnodes -o yaml` | the blocks Cilium allocated to each node, per pool |
| `kubectl get ciliumpodippools` | the multi-pool pools |
| `kubectl describe pod <pod>` | `FailedCreatePodSandBox` events with the IPAM error |

## Hands-on lab

Start (or restart) the lab. Setup builds a brand-new cluster and installs
Cilium in multi-pool IPAM mode, which takes a few minutes:

```bash
make lab CH=50
```

Cilium's `default` pool is `10.10.0.0/16` with `/27` blocks. The lab has three
namespaces:

- `ch50-ipam`: the Pod `client` (netshoot, on the default pool), to test from with `kubectl -n ch50-ipam exec client -- curl ...`
- `ch50-blue`: annotated with the pool `blue`; the Deployment `api` (3 replicas, agnhost on port 8080) cannot start
- `ch50-batch`: annotated with the pool `small` (`10.30.0.0/27`, `/28` blocks); the Deployment `batch` has 40 replicas, and only some of them run

Answer files go in `/tmp/kbook/ch50/`, which already exists. Type `make check
CH=50` after each task. Solutions: `chapters/50-ipam/lab/solutions.md`.

### Task 1: What Kubernetes allocates

Find the ranges Kubernetes itself hands out, which this cluster's Pods do not
use.

- `/tmp/kbook/ch50/cluster-cidr`: the cluster CIDR the controller manager divides into node ranges
- `/tmp/kbook/ch50/node-addresses`: the number of addresses in `kbook-worker`'s `podCIDR`

### Task 2: The missing pool

Get the `api` Pods in `ch50-blue` running with addresses from the pool their
namespace asks for.

- A `CiliumPodIPPool` named `blue` with the single CIDR `10.20.0.0/16` and a mask size of 28
- All 3 `api` Pods are running, with addresses from `10.20.0.0/16`
- `client` reaches an `api` Pod at its address on port 8080

### Task 3: An exhausted pool

Get all 40 `batch` Pods running, without changing the Deployment or the
namespace's annotation.

- Pool `small` still contains `10.30.0.0/27` and a mask size of 28, and every range in it is inside `10.30.0.0/16`
- The Deployment `batch` has 40 ready replicas, each with an address from pool `small`

### Task 4: One Pod, another pool

Run one Pod on the `blue` pool in a namespace that otherwise uses the default
pool.

- Pod `metrics` in `ch50-ipam`, running image `registry.k8s.io/e2e-test-images/agnhost:2.66.1` with the arguments `netexec --http-port=8080`
- Its address is from pool `blue`, and `client` reaches it on port 8080
- The namespace `ch50-ipam` itself has no pool annotation, and `client` keeps its address from the default pool

## Exam tips

> **Exam tip:** When Pods are `ContainerCreating` and the node is `Ready`,
> read the Pod's events before anything else. `FailedCreatePodSandBox`
> followed by an IPAM error means the network plugin could not give out an
> address; the fix is in the pool or the node's range, not in the Pod.

> **Exam tip:** Check which IPAM a cluster uses before you answer anything
> about Pod ranges: `cilium config view | grep ipam`, or the CNI configuration
> on a node for other plugins. The Node's `podCIDR` only matters in
> host-scope modes.

> **Exam tip:** `kubectl explain` does not help with `CiliumPodIPPool` fields
> until the CRD is installed, and it is `v2alpha1`, not `v2`. On
> `docs.cilium.io`, the *IP Address Management* section has a page per mode,
> with a complete multi-pool example.

## Common mistakes

- **Trusting `spec.podCIDR`.** In cluster-pool and multi-pool modes, Pod
  addresses come from Cilium's pools, not from the Node object.
- **Overlapping ranges.** A Pod range that overlaps the Service range, the
  node network, or another cluster's Pod range causes failures that look
  like routing bugs.
- **Writing `cilium.io/v2`** for a `CiliumPodIPPool`. The API version is
  `cilium.io/v2alpha1`; `kubectl apply` answers `no matches for kind`.
- **A namespace annotated with a pool that does not exist.** Its Pods wait
  forever in `ContainerCreating` with `pool not (yet) available`.
- **Counting 16 Pods per `/28`.** The first and last address of each block are
  not used by default, so a `/28` holds 14.
- **Shrinking or replacing a range in use.** Add ranges; remove one only when
  no Pod has an address from it.

<!-- QUESTIONS:START -->

## End-of-chapter questions

**1.** `CKNE` The controller manager runs with `--cluster-cidr=10.244.0.0/16` and `--node-cidr-mask-size=24`. What does it do with them?

- **A.** It gives every Pod an address from `10.244.0.0/16`
- **B.** It writes one `/24` from `10.244.0.0/16` into each Node's `spec.podCIDR`
- **C.** It configures kube-proxy's Service range
- **D.** It creates a CNI configuration on each node

**2.** `CKNE` With a cluster CIDR of `/16` and a node mask of `/24`, how many nodes can get a Pod range?

- **A.** 16
- **B.** 110
- **C.** 256
- **D.** 65,536

**3.** `CKNE` Why do many clusters use a `/24` per node, even though the kubelet runs at most 110 Pods by default?

- **A.** The CNI specification requires it
- **B.** It leaves room for more Pods than the default, and a `/24` is easy to read; the cost is fewer node blocks per cluster CIDR
- **C.** Smaller blocks are not routable
- **D.** kube-proxy only supports `/24` ranges

**4.** `CKNE` Cilium runs in cluster-pool mode. `kubectl get node w1 -o jsonpath='{.spec.podCIDR}'` shows `10.244.1.0/24`, but Pods on `w1` have `10.0.2.x` addresses. What is true?

- **A.** The cluster is broken: Pods must use the node's podCIDR
- **B.** Cilium's operator allocated its own block (recorded in the CiliumNode object) and ignores the Node's podCIDR; this is normal in cluster-pool mode
- **C.** kube-proxy translated the addresses
- **D.** The Pods were created before the CNI was installed

**5.** `CKNE` In Cilium multi-pool IPAM, how does a Pod end up with an address from the pool `blue`?

- **A.** Its Deployment has the label `pool: blue`
- **B.** Its namespace or the Pod itself has the annotation `ipam.cilium.io/ip-pool: blue`
- **C.** The node has the label `cilium.io/pool=blue`
- **D.** The Pod lists `blue` in `spec.dnsConfig`

**6.** `CKNE` A Deployment's Pods are scheduled to a Ready node but stay in `ContainerCreating`. Their events show `FailedCreatePodSandBox ... all CIDR ranges are exhausted`. What is the cause?

- **A.** The image cannot be pulled
- **B.** The IPAM pool or range the Pods use has no free address
- **C.** The Service has no endpoints
- **D.** The node's kubelet is out of memory

**7.** `CKNE` How many Pods fit in one `/28` block of a Cilium `CiliumPodIPPool` with default settings?

- **A.** 16
- **B.** 15
- **C.** 14
- **D.** 8

**8.** `CKNE` Which fix for address exhaustion keeps running Pods untouched?

- **A.** Replace the pool's CIDR with a larger one
- **B.** Add a second CIDR to the pool (multi-pool or Calico)
- **C.** Change the cluster CIDR in the controller manager
- **D.** Restart all nodes

**9.** `CKNE` Which ranges must not overlap in a cluster?

- **A.** Only the Pod range and the Service range
- **B.** The Pod range, the Service range, and the network the nodes sit on (and other clusters' Pod ranges, if clusters connect)
- **C.** None: Kubernetes translates overlapping ranges
- **D.** Only the node network and the Service range

**10.** `CKNE` Calico assigns addresses from IP pools in blocks. What happens when a node's blocks are full and the pool has no free block left?

- **A.** The node joins another cluster
- **B.** Calico borrows single addresses from other nodes' blocks
- **C.** Calico switches the node to host-local IPAM
- **D.** The kubelet deletes old Pods

**11. (Task)** `CKNE` On a kubeadm cluster, find the cluster CIDR, the node mask size, and the range assigned to node `node1`.

**12. (Task)** `CKNE` Cilium runs in multi-pool mode. Give all Pods in namespace `analytics` addresses from `10.50.0.0/16`, in `/27` blocks.

**13. (Task)** `CKNE` Pods of the Deployment `jobs` in namespace `batch` (pool `batch`, CIDR `10.60.0.0/26`) stay in `ContainerCreating` with an IPAM error. Fix it without touching the Deployment.

<details>
<summary>Answers</summary>

**1. B.** Kubernetes only offers each node a range. The CNI plugin decides whether to use it; Kubernetes never assigns a Pod address itself.

**2. C.** There are 2^(24-16) = 256 blocks of `/24` in a `/16`. Each block has 256 addresses, enough for the kubelet's default of 110 Pods.

**3. B.** A `/25` (128 addresses) would also fit 110 Pods and double the number of possible nodes. The node mask is a trade-off between Pods per node and nodes per cluster.

**4. B.** In cluster-pool mode Cilium owns IPAM. `kubectl get ciliumnode w1 -o yaml` shows the block it uses, under `spec.ipam.podCIDRs`.

**5. B.** The annotation can be on the Pod or on its namespace; without one, the Pod uses the pool named `default`.

**6. B.** The plugin could not give the sandbox an address, so the Pod never starts. Grow the pool (multi-pool, Calico) or add capacity (host-scope modes).

**7. C.** `allowFirstIP` and `allowLastIP` are `false` by default, so the first and last of the 16 addresses are not handed out.

**8. B.** Adding a range gives nodes new blocks to claim. Replacing or removing a range that Pods use takes their addresses out from under them; changing the cluster CIDR does not affect existing node ranges.

**9. B.** Overlaps make routing ambiguous: a packet to an address in two ranges can only follow one route. Multi-cluster routing (Chapter 62) also needs distinct Pod ranges.

**10. B.** Calico claims blocks (`/26` by default) per node as needed, and, when no block is free, borrows addresses from other blocks. Only when the pool has no address at all do Pods fail.

**11.**

```bash
ssh controlplane
sudo grep -E 'cluster-cidr|node-cidr-mask-size' /etc/kubernetes/manifests/kube-controller-manager.yaml
kubectl get node node1 -o jsonpath='{.spec.podCIDR}{"\n"}'
```

Without a `--node-cidr-mask-size` flag the default is `/24` for IPv4. Then check which IPAM the CNI plugin uses before assuming Pods get addresses from that range.

**12.**

```bash
kubectl apply -f - <<'EOF'
apiVersion: cilium.io/v2alpha1
kind: CiliumPodIPPool
metadata:
  name: analytics
spec:
  ipv4:
    cidrs: ["10.50.0.0/16"]
    maskSize: 27
EOF
kubectl annotate namespace analytics ipam.cilium.io/ip-pool=analytics
kubectl -n analytics rollout restart deployment
kubectl -n analytics get pods -o wide
```

The annotation applies to new Pods, so restart the existing workloads. Check the new addresses with `-o wide`.

**13.**

```bash
kubectl -n batch describe pod <a-waiting-pod> | grep -A2 FailedCreatePodSandBox
kubectl patch ciliumpodippool batch --type=merge \
  -p '{"spec":{"ipv4":{"cidrs":["10.60.0.0/26","10.60.1.0/24"]}}}'
kubectl -n batch get deployment jobs
```

The events show `all CIDR ranges are exhausted`. Keep the existing range in the list and add one; the waiting Pods start once their nodes claim blocks from it.

</details>

<!-- QUESTIONS:END -->

## Further reading

- Kubernetes documentation: [kube-controller-manager](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/) (`--cluster-cidr`, `--node-cidr-mask-size`)
- Cilium documentation: [IP Address Management](https://docs.cilium.io/en/stable/network/concepts/ipam/), including the cluster-pool and multi-pool pages
- Calico documentation: [Get started with IP address management](https://docs.tigera.io/calico/latest/networking/ipam/get-started-ip-addresses)
