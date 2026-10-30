# Chapter 06 lab: solutions

Try each task before reading its solution. Every command passes `-n`
explicitly, because the tasks use several namespaces.

## Task 1: find `lost-cat`

```bash
kubectl get pods -A --field-selector metadata.name=lost-cat
kubectl get pods -A --field-selector metadata.name=lost-cat \
  -o jsonpath='{.items[0].metadata.namespace}' > /tmp/ch06-ns.txt
```

`kubectl get pods -A | grep lost-cat` finds it too. The namespace changes every
time the lab is set up, so look rather than remember.

## Task 2: the payments namespace

```bash
kubectl create namespace ch06-payments
kubectl label namespace ch06-payments team=payments
kubectl -n ch06-payments run ledger --image=nginx:1.27 --labels=app=ledger
```

Declaratively, a namespace with labels is short enough to write by hand:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ch06-payments
  labels:
    team: payments
```

## Task 3: release the degraded Pod

Find it by its annotation; annotations cannot be used in `-l`, so filter with
JSONPath:

```bash
kubectl -n ch06-shop get pods -o jsonpath='{.items[?(@.metadata.annotations.status=="degraded")].metadata.name}{"\n"}'
kubectl -n ch06-shop label pod <that-pod> app=queue-debug --overwrite
kubectl -n ch06-shop get pods -L app
kubectl -n ch06-shop get deployment queue
```

`kubectl describe pods -n ch06-shop -l app=queue | grep -E '^Name:|status='`
works as a quick visual search too. After the relabel, the ReplicaSet no longer
counts the Pod, removes itself as the Pod's owner, and starts a replacement.
`--overwrite` is required because the label `app` already exists.

## Task 4: Pods that are not running

```bash
kubectl -n ch06-shop get pods --field-selector status.phase!=Running
kubectl -n ch06-shop get pods --field-selector status.phase!=Running -o name > /tmp/ch06-not-running.txt
```

The answer is `import-done` (phase `Succeeded`, shown as `Completed`),
`import-failed` (phase `Failed`, shown as `Error`), and `reports` (`Pending`).
`-o name` prints `pod/NAME`; the check accepts that, or bare names.

## Task 5: schedule `fast-io`

```bash
kubectl -n ch06-blue describe pod fast-io      # Node-Selectors: ch06.kbook.io/disk=ssd, FailedScheduling
kubectl get nodes
kubectl label node kbook-worker ch06.kbook.io/disk=ssd
kubectl -n ch06-blue get pod fast-io -o wide
```

A Pod's `nodeSelector` cannot be changed on a running Pod, and deleting and
recreating it without the selector would not be the same Pod. Labelling a node
is the intended fix. The Pod leaves `Pending` within seconds of the label
appearing, because the scheduler retries unschedulable Pods when nodes change.
Label one worker only: on the control plane node, the Pod would stay `Pending`
because of the control plane's taint (Chapter 17).
