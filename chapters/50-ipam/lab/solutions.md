# Chapter 50 lab: solutions

All commands run on your machine, in the repository folder.

## Task 1: What Kubernetes allocates

```bash
docker exec kbook-control-plane grep cluster-cidr /etc/kubernetes/manifests/kube-controller-manager.yaml
kubectl get node kbook-worker -o jsonpath='{.spec.podCIDR}{"\n"}'
```

The flag is `--cluster-cidr=10.244.0.0/16`. The node's range changes with
every cluster build, but it is always a `/24` here (for example
`10.244.2.0/24`), and a `/24` has 2^(32-24) = 256 addresses:

```bash
echo 10.244.0.0/16 > /tmp/kbook/ch50/cluster-cidr
echo 256 > /tmp/kbook/ch50/node-addresses
```

Compare with `kubectl get pods -A -o wide`: the Pods have addresses from
Cilium's pools (`10.10.0.0/16` and others), not from these ranges.

## Task 2: The missing pool

```bash
kubectl -n ch50-blue get pods
kubectl -n ch50-blue describe pod <an-api-pod> | grep FailedCreatePodSandBox
```

The events say `unable to allocate from pool "blue" ... pool not (yet)
available`. Create it:

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
kubectl -n ch50-blue rollout status deployment/api
kubectl -n ch50-blue get pods -o wide
```

The waiting Pods retry and start on their own. Test from `client` with one of
the addresses:

```bash
kubectl -n ch50-ipam exec client -- curl -s http://<api-pod-ip>:8080/clientip
```

## Task 3: An exhausted pool

```bash
kubectl -n ch50-batch get deployment batch
kubectl -n ch50-batch describe pod <a-waiting-pod> | grep FailedCreatePodSandBox
```

The events say `all CIDR ranges are exhausted`: `10.30.0.0/27` holds two `/28`
blocks of 14 usable addresses. Add a range, keeping the old one:

```bash
kubectl patch ciliumpodippool small --type=merge \
  -p '{"spec":{"ipv4":{"cidrs":["10.30.0.0/27","10.30.1.0/26"]}}}'
kubectl -n ch50-batch rollout status deployment/batch
```

`10.30.1.0/26` adds four blocks, 56 addresses; anything inside `10.30.0.0/16`
that does not overlap works.

## Task 4: One Pod, another pool

```bash
kubectl -n ch50-ipam apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: metrics
  annotations:
    ipam.cilium.io/ip-pool: blue
spec:
  containers:
    - name: metrics
      image: registry.k8s.io/e2e-test-images/agnhost:2.66.1
      args: ["netexec", "--http-port=8080"]
EOF
kubectl -n ch50-ipam get pod metrics -o wide
kubectl -n ch50-ipam exec client -- curl -s http://<metrics-ip>:8080/clientip
```

The annotation on the Pod overrides the namespace's choice (here: none, so the
default pool) for that one Pod.

`make teardown CH=50` removes the answer folder and deletes the cluster; `make
cluster` builds the default one again.
