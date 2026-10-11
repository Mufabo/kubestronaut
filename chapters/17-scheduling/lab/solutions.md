# Chapter 17 lab: solutions

Try each task before reading its solution. The commands below pass
`-n ch17-sched` explicitly, because the lab does not change your default
namespace. The setup has labelled `kbook-worker` with `disk=ssd` and tainted
`kbook-worker2` with `maintenance=true:NoSchedule`.

## Task 1: `pinned` on the SSD node

```bash
cat <<'YAML' | kubectl -n ch17-sched apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pinned
spec:
  nodeSelector:
    disk: ssd
  containers:
    - name: pinned
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML
kubectl -n ch17-sched get pod pinned -o wide
```

A `nodeSelector` is a required filter. Only `kbook-worker` carries the label, so
the Pod lands there.

## Task 2: `tolerant` on the maintenance node

```bash
cat <<'YAML' | kubectl -n ch17-sched apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: tolerant
spec:
  nodeSelector:
    kubernetes.io/hostname: kbook-worker2
  tolerations:
    - key: maintenance
      operator: Equal
      value: "true"
      effect: NoSchedule
  containers:
    - name: tolerant
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML
```

The toleration lets the Pod onto the tainted node, and the selector puts it there.
Without the selector, the Pod could run on any untainted node.

## Task 3: `cache`, anti-affinity on hostname

```bash
cat <<'YAML' | kubectl -n ch17-sched apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cache
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cache
  template:
    metadata:
      labels:
        app: cache
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - topologyKey: kubernetes.io/hostname
              labelSelector:
                matchLabels:
                  app: cache
      containers:
        - name: cache
          image: busybox:1.36
          command: ["sleep", "3600"]
YAML
kubectl -n ch17-sched rollout status deployment/cache
```

The rule is in the Pod template, so the Pods carry it. With one replica it is
satisfied at once.

## Task 4: the `ch17-batch` PriorityClass and `urgent`

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: ch17-batch
value: 100000
description: Batch work that may run ahead of ordinary Pods
YAML
cat <<'YAML' | kubectl -n ch17-sched apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: urgent
spec:
  priorityClassName: ch17-batch
  containers:
    - name: urgent
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML
```

The PriorityClass is cluster-scoped, so it has no namespace. Reset removes it.

## Task 5: the static Pod for the scheduler

```bash
kubectl -n kube-system get pods -o jsonpath='{range .items[?(@.metadata.ownerReferences[0].kind=="Node")]}{.metadata.name}{"\n"}{end}' | grep kube-scheduler > /tmp/ch17-static.txt
```

The owner reference of kind `Node` marks a static Pod's mirror. The name ends with
the control-plane node's name, so the file holds `kube-scheduler-kbook-control-plane`.

## Why these checks accept any correct method

Each check reads the Pod's node, its tolerations and affinity, the Deployment's
rule, the PriorityClass value and the Pod's class, and the answer file. You can
create each object with YAML or with imperative commands, and the checks do not
care which.
