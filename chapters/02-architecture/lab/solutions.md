# Chapter 02 lab: solutions

Try each task before reading its solution. The lab is read-only exploration.
Answers are written to files in `/tmp`.

## Task 1: the control plane node

```bash
kubectl get nodes
kubectl get nodes --show-labels        # the role appears as a label
kubectl get nodes -l node-role.kubernetes.io/control-plane -o name
```

Save just the name (without the `node/` prefix):

```bash
kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[0].metadata.name}' > /tmp/ch02-cp-node.txt
```

The `ROLES` column in `kubectl get nodes` is derived from labels of the form
`node-role.kubernetes.io/<role>`.

## Task 2: the etcd Pod

```bash
kubectl -n kube-system get pods
kubectl -n kube-system get pods -l component=etcd -o jsonpath='{.items[0].metadata.name}' > /tmp/ch02-etcd-pod.txt
```

kubeadm-created clusters (including kind) label their control plane Pods with
`component=<name>` and `tier=control-plane`.

## Task 3: static Pods

```bash
kubectl -n kube-system get pods -o wide
kubectl -n kube-system get pod <one of them> -o yaml | grep -A3 ownerReferences
```

Mirror Pods for static Pods have an owner of `kind: Node`. Their names end with
the node name. On a single control plane cluster, these are `kube-apiserver`,
`etcd`, `kube-controller-manager`, and `kube-scheduler`.

```bash
kubectl -n kube-system get pods -o jsonpath='{range .items[?(@.metadata.ownerReferences[0].kind=="Node")]}{.metadata.name}{"\n"}{end}' > /tmp/ch02-static-pods.txt
```

Notice what is *not* on the list: `kube-proxy` (a DaemonSet) and `coredns`
(a Deployment). They are managed through the API like any workload.

## Task 4: where the Pod runs

```bash
kubectl -n ch02-arch get pod where-am-i -o wide
kubectl -n ch02-arch get pod where-am-i -o jsonpath='{.spec.nodeName}' > /tmp/ch02-pod-node.txt
```

`spec.nodeName` is filled in by the scheduler when it *binds* the Pod to a node.

## Task 5: API group and version for Deployments

```bash
kubectl api-resources | grep -i deployment
kubectl api-resources --api-group=apps
echo apps/v1 > /tmp/ch02-deployment-api.txt
```

In a manifest this becomes `apiVersion: apps/v1`. Core resources such as Pods
have an empty group, so their `apiVersion` is just `v1`.
