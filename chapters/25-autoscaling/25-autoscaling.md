# Chapter 25: Autoscaling: the HPA, the VPA, and the cluster autoscaler

> **Exams:** CKA
> **Difficulty:** Advanced
> **Time:** ~55 min reading, ~35 min lab
> **Lab tier:** 1 (kind, with metrics-server installed)
> **Prerequisites:** Chapter 05 (Controllers), Chapter 10 (Probes and resources)

## Learning objectives

After this chapter you can:

- Explain why the HPA needs resource requests, and how it computes a desired replica count from observed utilization
- Write an `autoscaling/v2` HorizontalPodAutoscaler with a CPU target, minimum and maximum replicas, and a scale-down window
- Explain what metrics-server provides, and what `kubectl top` and the HPA read from it
- Distinguish the three autoscaling directions: horizontal (more Pods), vertical (bigger Pods), and cluster (more nodes)
- Recognize a VPA's recommendation and update modes, and say when a cluster autoscaler adds or removes nodes
- Find the served API version for an autoscaling kind with `kubectl api-resources`

## Concepts

### Three directions of scaling

A workload can grow in three ways, and each is handled by a different component:

- **Horizontal** scaling changes the number of Pods. The HorizontalPodAutoscaler
  (HPA) does this for a Deployment, a StatefulSet, or a ReplicaSet.
- **Vertical** scaling changes the size of each Pod's requests and limits. The
  Vertical Pod Autoscaler (VPA) does this. It is an add-on, not part of the core
  project.
- **Cluster** scaling changes the number of nodes. The cluster autoscaler adds a
  node when Pods are Pending for lack of room, and removes a node that is mostly
  empty. It needs integration with the cloud's node groups.

These do not replace each other. A horizontal autoscaler needs headroom on the
nodes, and the cluster autoscaler provides it; a vertical autoscaler changes the
requests the scheduler uses, so it changes where Pods fit.

### How the HPA computes a replica count

The HPA controller reads a metric every 15 seconds by default, and it works out a
desired replica count:

```text
desiredReplicas = ceil( currentReplicas * currentMetricValue / targetMetricValue )
```

For CPU, the metric is utilization: usage divided by the Pod's **CPU request**. That
is why the HPA needs requests. Without a request, there is no utilization to compare,
and the HPA cannot compute a value. A target of 50% with one Pod at 100% gives
`ceil(1 * 100 / 50) = 2` replicas. The result is capped by `maxReplicas`, and
floored by `minReplicas`.

The HPA scales up without delay by default, and it scales down slowly, because a
noisy metric would otherwise make the number of Pods oscillate. The `behavior` field
controls both directions:

- `scaleUp` and `scaleDown` each take `policies` (how many Pods or what percentage
  may change per period) and a `stabilizationWindowSeconds`.
- The scale-down stabilization window takes the highest recommendation over the
  window, so a brief dip does not remove Pods.

### Metric sources

An `autoscaling/v2` HPA can read four kinds of metric:

- `resource` is CPU or memory, read from metrics-server (see below). This is the
  common case.
- `containerResource` is one container's CPU or memory, for Pods with several containers.
- `pods` and `object` read custom metrics, which an adapter serves through the
  `custom.metrics.k8s.io` API.
- `external` reads metrics outside the cluster, through the `external.metrics.k8s.io` API.

Custom and external metrics need an adapter installed, which is why the lab uses
resource metrics only.

### metrics-server

metrics-server collects CPU and memory from every kubelet and serves them through
the `metrics.k8s.io` API. `kubectl top` reads that API, and so does the HPA. Without
it, `kubectl top` fails with `Metrics API not available`, and the HPA reports
`unknown` for the metric.

The lab cluster runs metrics-server, installed with the pinned version in
`versions.env`. Its kind-specific detail is that kind's kubelets use self-signed
certificates, so the lab's copy is started with `--kubelet-insecure-tls`. That flag
is for test clusters only: on a production cluster, the kubelets' certificates
should be valid.

### The VPA

The VPA watches a Pod's usage over time and recommends requests that fit it. It runs
in three modes:

- `Off` only writes recommendations into the VPA object, and changes nothing.
- `Initial` sets the requests when a Pod is created, and never changes a running Pod.
- `Auto` evicts Pods that drift from their recommendation, so that they restart with new requests.

A VPA and an HPA on the same CPU metric fight each other: one changes the requests,
the other changes the replica count. Use the VPA in `Off` mode alongside an HPA, or
scale one of them on a different metric.

### The cluster autoscaler

The cluster autoscaler watches for Pods the scheduler cannot place. When a Pod is
Pending because no node has room, it asks the cloud to add a node to a node group,
and when a node is mostly empty for a while, and its Pods can move, it removes the
node. It works through a provider plugin, so its behaviour depends on the cloud.
kind has no node groups, so this cluster has no cluster autoscaler.

Pods that the autoscaler must not move need a `cluster-autoscaler.kubernetes.io/safe-to-evict: "false"`
annotation, or a PodDisruptionBudget that the eviction would break.

## Guided walkthrough

The walkthrough works in the Namespace `ch25-demo`. The outputs below are trimmed:
ages and metric values differ on your cluster, and they move from one sample to the
next. The objects are named `demo-...` so they do not clash with the lab. The lab
later in this chapter uses its own namespace, `ch25-scale`. Create the demo namespace with
`kubectl create namespace ch25-demo`.

### Check that metrics are available

```bash
kubectl top nodes
```

```text
NAME                  CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
kbook-control-plane   234m         1%       1391Mi          18%
kbook-worker          665m         4%       1461Mi          19%
kbook-worker2         126m         0%       654Mi           8%
```

Metrics come from metrics-server, and the HPA reads the same numbers. If this command
fails, the HPA cannot scale either.

### Create a CPU-bound Deployment with a request

The HPA needs a request to measure utilization against. Create a Deployment that
burns CPU, give it a request and a limit, and wait for it:

```bash
kubectl -n ch25-demo create deployment demo-burn --image=busybox:1.36 --replicas=1 -- sh -c 'while true; do :; done'
kubectl -n ch25-demo set resources deployment demo-burn --requests=cpu=100m --limits=cpu=500m
kubectl -n ch25-demo rollout status deployment/demo-burn --timeout=120s
```

```text
deployment.apps/demo-burn created
deployment "demo-burn" successfully rolled out
```

The request is `100m`, so the HPA's utilization is usage over 100 millicores. The
limit caps each Pod at half a core.

### Create the HPA and watch it scale

Create an HPA that targets 50% CPU utilization, between 1 and 3 replicas, and wait a
minute before you look:

```bash
kubectl -n ch25-demo autoscale deployment demo-burn --cpu=50% --min=1 --max=3
sleep 45
kubectl -n ch25-demo get hpa demo-burn
kubectl -n ch25-demo get deployment demo-burn
```

```text
horizontalpodautoscaler.autoscaling/demo-burn autoscaled
NAME        REFERENCE              TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
demo-burn   Deployment/demo-burn   cpu: 501%/50%   1         3         1          45s
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
demo-burn   1/3     3            1           47s
```

The HPA sees 501% against a target of 50%, and it asks for 3 replicas, which is its
maximum. The Deployment now has three Pods, with one ready so far. `TARGETS` shows
the current value and the target, so you can read the HPA's view at a glance.

### Read the HPA's decision

Describe the HPA and read its conditions:

```bash
kubectl -n ch25-demo get hpa demo-burn -o jsonpath='{.apiVersion} {.spec.metrics[0].resource.name} {.spec.metrics[0].resource.target.averageUtilization}{"\n"}'
kubectl -n ch25-demo describe hpa demo-burn
```

```text
autoscaling/v2 cpu 50
Conditions:
  Type            Status  Reason            Message
  ----            ------  ------            -------
  AbleToScale     True    SucceededRescale  the HPA controller was able to update the target scale to 3
  ScalingActive   True    ValidMetricFound  the HPA was able to successfully calculate a replica count from cpu resource utilization (percentage of request)
  ScalingLimited  True    TooManyReplicas   the desired replica count is more than the maximum replica count
```

`ScalingLimited` says why the HPA stopped at three: the calculated count was higher
than `maxReplicas`. `ValidMetricFound` confirms that the metric was read. A missing
request would show `FailedGetResourceMetric` here instead.

Clean up the demo:

```bash
kubectl delete namespace ch25-demo
```

```text
namespace "ch25-demo" deleted
```

## Hands-on lab

The lab works like a KodeKloud lab: one task at a time, a check after each, and
progress that is saved between sessions.

```bash
make lab CH=25       # set up the lab and show task 1
make check CH=25     # check the current task; if it is right, show the next
make question CH=25  # show the current task again
make reset CH=25     # back to the starting state and task 1
make verify CH=25    # check every task at once
```

Everything happens in the Namespace `ch25-scale`: use `-n ch25-scale` on every command,
or run `make use-namespace CH=25` once. The setup creates a Deployment `api`, one
replica, a CPU request of `100m`, and a busy loop. Task 1 creates the HPA, and Tasks 2
to 4 depend on it. Task 5 does not. Scaling takes a minute or two, so Task 2 waits
for it. The answers go to two files under `/tmp`, which teardown removes.

Full solutions are in [`lab/solutions.md`](lab/solutions.md).

### Task 1: An HPA for `api`

Create a HorizontalPodAutoscaler named `api` in `ch25-scale` with the following specification.

- Uses the `autoscaling/v2` API
- Targets the Deployment `api`
- Minimum 1 replica, maximum 4
- Scales on CPU, with an average utilization target of 50%

### Task 2: Let the Deployment scale

Wait until the Deployment `api` has at least 2 ready replicas. The HPA scales it under
its CPU load, and that takes a minute or two.

- Deployment `api` has at least 2 ready replicas

### Task 3: Record the metric the HPA reads

Write the name of the resource metric that the HPA reports in its status (the value of
`status.currentMetrics[0].resource.name`) into `/tmp/ch25-metric.txt`.

- The HPA's status names the CPU metric
- File `/tmp/ch25-metric.txt` holds `cpu`

### Task 4: A scale-down window

Set the HPA `api` to wait 60 seconds before it scales down, using the `behavior` field of
its spec, in the `scaleDown` section.

- HPA `api`: `behavior.scaleDown.stabilizationWindowSeconds` is `60`

### Task 5: Record the API version

Write the API version that serves HorizontalPodAutoscalers in the `autoscaling` group, for
example `autoscaling/v2`, into `/tmp/ch25-hpa-api.txt`.

- File `/tmp/ch25-hpa-api.txt` holds the served version, such as `autoscaling/v2`

## Exam tips

> **Exam tip:** `kubectl autoscale deployment NAME --cpu=50% --min=1 --max=4` writes the HPA in one command. The `--cpu-percent` flag is deprecated, so use `--cpu` with a percentage.
>
> **Exam tip:** An HPA that never scales is usually a missing request or missing metrics. `kubectl describe hpa NAME` names the failing condition, such as `FailedGetResourceMetric` or `unknown`, and it points to the cause.
>
> **Exam tip:** Read `kubectl top pods` before you debug an HPA. If it fails, metrics-server is the problem, not the HPA.

## Common mistakes

- Creating a CPU-based HPA for Pods with no CPU request. The utilization cannot be computed, and the HPA reports `unknown`.
- Setting a target above what the Pods can ever use, so the HPA never scales up.
- Running a VPA in `Auto` mode alongside an HPA on the same CPU metric. They change the same workload from two sides.
- Expecting `kubectl top` to work on a cluster without metrics-server. It fails with `Metrics API not available`.
- Using a `minReplicas` of 0 without the feature that allows it. The HPA refuses it on the default configuration.
- Expecting the cluster autoscaler to add nodes for Pods that fail for another reason. It acts only on Pods the scheduler cannot place for lack of room.

<!-- QUESTIONS:START -->

## End-of-chapter questions

**1.** `CKA` The HPA's CPU target is 50%, and the Deployment has 2 replicas running at an average of 100% utilization. What replica count does the HPA compute, before minReplicas and maxReplicas apply?

- **A.** 2
- **B.** 3
- **C.** 4
- **D.** 1

**2.** `CKA` Why does a CPU-based HPA need its Pods to set a CPU request?

- **A.** The request is the price the HPA pays per replica
- **B.** Utilization is measured as usage divided by the request, so without a request there is nothing to compare
- **C.** The scheduler refuses to run Pods with no request
- **D.** The request sets the HPA's maximum replicas

**3.** `CKA` Which component supplies the CPU and memory numbers that `kubectl top` and the HPA read?

- **A.** The kubelet alone, through its own API
- **B.** metrics-server, which serves the metrics.k8s.io API
- **C.** CoreDNS
- **D.** The cluster autoscaler

**4.** `CKA` A VerticalPodAutoscaler is in `Off` mode. What does it do with its recommendations?

- **A.** It evicts Pods to apply them
- **B.** It writes them into the VPA object and changes nothing in the workload
- **C.** It applies them to new Pods only
- **D.** It deletes the HPA

**5.** `CKA` When does the cluster autoscaler add a node?

- **A.** Every time a Deployment is scaled up
- **B.** When Pods are Pending because no existing node has room for them, and the node group can grow
- **C.** When a node reports a Ready condition
- **D.** Once a day, regardless of load

**6.** `CKA` What does the `stabilizationWindowSeconds` setting of `scaleDown` in an HPA's `behavior` do?

- **A.** It delays the first scale-up after a Pod starts
- **B.** It makes the HPA use the highest recommendation over the window, so a short dip in load does not remove Pods
- **C.** It sets how long a Pod has to be ready before it counts
- **D.** It removes a Pod after the window expires

**7.** `CKA` Which API serves custom metrics to an HPA that uses `type: Pods` or `type: Object`?

- **A.** metrics.k8s.io
- **B.** custom.metrics.k8s.io
- **C.** apps/v1
- **D.** policy/v1

**8. (Task)** `CKA` In namespace `prod`, the Deployment `web` exists. Create a HorizontalPodAutoscaler named `web` that targets it with 2 to 6 replicas and a CPU target of 70% average utilization. Show its minimum and maximum replicas.

**9. (Task)** `CKA` In namespace `prod`, change the HPA `web` so that it scales down only after 300 seconds of lower load, and scales up with no waiting. Show the scale-down window.

**10. (Task)** `CKA` Write the name of the APIService that serves resource metrics to `kubectl top` and to the HPA into `/tmp/ch25-q10.txt`, and nothing else.

**11. (Task)** `CKA` In namespace `prod`, count the Pods that have CPU metrics available with `kubectl top pods`, and write the number to `/tmp/ch25-q11.txt`, and nothing else.

<details>
<summary>Answers</summary>

**1. C.** `desiredReplicas = ceil(currentReplicas * currentMetric / targetMetric)` gives `ceil(2 * 100 / 50) = 4`. The minimum and maximum then bound the result.

**2. B.** The HPA's CPU metric is utilization relative to each Pod's CPU request. Without a request, the HPA cannot compute a utilization percentage, and it reports the metric as unknown.

**3. B.** metrics-server collects CPU and memory from each kubelet and serves them through the metrics.k8s.io API. Both `kubectl top` and the HPA read that API.

**4. B.** `Off` computes and publishes recommendations without applying them. `Initial` applies them only when Pods are created, and `Auto` evicts Pods so they restart with the new requests.

**5. B.** The cluster autoscaler reacts to Pods the scheduler cannot place for lack of capacity, and it asks the cloud's node group to add a node. It also removes underused nodes whose Pods can be moved.

**6. B.** The scale-down stabilization window keeps the highest recommended replica count seen during the window. That prevents a brief drop in utilization from removing Pods that a rebound would need.

**7. B.** metrics.k8s.io serves the resource metrics from metrics-server. Custom metrics come through custom.metrics.k8s.io, which an adapter serves. External metrics use external.metrics.k8s.io.

**8.**

```bash
cat <<'YAML' | kubectl -n prod apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  minReplicas: 2
  maxReplicas: 6
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
YAML
kubectl -n prod get hpa web -o jsonpath='{.spec.minReplicas}/{.spec.maxReplicas}{"\n"}'
```

The `autoscaling/v2` API is the one that supports the `metrics` list and `behavior`.

**9.**

```bash
kubectl -n prod patch hpa web --type=merge -p '{"spec":{"behavior":{"scaleUp":{"stabilizationWindowSeconds":0},"scaleDown":{"stabilizationWindowSeconds":300}}}}'
kubectl -n prod get hpa web -o jsonpath='{.spec.behavior.scaleDown.stabilizationWindowSeconds}{"\n"}'
```

`behavior` is a field of the HPA's spec, with `scaleUp` and `scaleDown` sections.
A window of `0` on `scaleUp` is the default, and it is set here to make the intent explicit.

**10.**

```bash
kubectl get apiservices v1beta1.metrics.k8s.io -o jsonpath='{.metadata.name}' > /tmp/ch25-q10.txt
cat /tmp/ch25-q10.txt
```

The APIService for resource metrics is `v1beta1.metrics.k8s.io`, and its availability
shows whether metrics-server is working.

**11.**

```bash
kubectl top pods -n prod --no-headers | wc -l | tr -d '[:space:]' > /tmp/ch25-q11.txt
cat /tmp/ch25-q11.txt
```

`kubectl top` lists only the Pods that have metrics, and `--no-headers` leaves
one line for each of them. In a namespace with no Pods, the answer is `0`.

</details>

<!-- QUESTIONS:END -->

## Further reading

- Kubernetes documentation: *Horizontal Pod Autoscaling*, *HorizontalPodAutoscaler Walkthrough*
- Kubernetes documentation: *Resource metrics pipeline*, *metrics-server*
- Kubernetes documentation: *Vertical Pod Autoscaler* (the project's README covers its modes), and the cluster autoscaler's FAQ for your cloud
- Chapter 26 next: troubleshooting I, applications and networking
