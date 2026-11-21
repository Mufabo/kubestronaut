# Chapter 51 lab: solutions

All commands run on your machine, in the repository folder.

## Task 1: Put Multus in charge

```bash
docker exec kbook-worker ls /etc/cni/net.d
```

```text
00-multus.conf.cilium_bak
05-cilium.conflist
```

Cilium's exclusive mode moved Multus's file aside. Turn it off, restart Cilium,
then restart Multus so it writes its file again:

```bash
helm upgrade cilium cilium --repo https://helm.cilium.io --version 1.20.5 \
  -n kube-system --reuse-values --set cni.exclusive=false
kubectl -n kube-system rollout restart daemonset/cilium
kubectl -n kube-system rollout status daemonset/cilium
kubectl -n kube-system rollout restart daemonset/kube-multus-ds
kubectl -n kube-system rollout status daemonset/kube-multus-ds
for n in kbook-control-plane kbook-worker kbook-worker2; do docker exec $n ls /etc/cni/net.d; done
```

`00-multus.conf` is first on every node. The `.cilium_bak` file is ignored (wrong
extension) and can stay.

## Task 2: The storage network

```bash
kubectl -n ch51-multus apply -f - <<'EOF'
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: storage
spec:
  config: |
    {
      "cniVersion": "1.0.0",
      "type": "macvlan",
      "master": "eth0",
      "mode": "bridge",
      "capabilities": {"ips": true},
      "ipam": {"type": "static"}
    }
EOF
```

## Task 3: Attach db and app

Add the annotation to each starting manifest, for example in
`chapters/51-multus/manifests/db.yaml`:

```yaml
metadata:
  name: db
  namespace: ch51-multus
  annotations:
    k8s.v1.cni.cncf.io/networks: '[{"name": "storage", "ips": ["172.18.100.21/24"]}]'
```

and `172.18.100.22/24` in `app.yaml`. Then:

```bash
kubectl apply -f chapters/51-multus/manifests/db.yaml -f chapters/51-multus/manifests/app.yaml
kubectl -n ch51-multus wait --for=condition=Ready pod/db pod/app
kubectl -n ch51-multus exec app -- ip -br addr
kubectl -n ch51-multus exec app -- ping -c2 172.18.100.21
```

If you created the Pods before adding the annotation, delete them first:
networks are attached only when a Pod starts.

## Task 4: A named interface

```bash
kubectl -n ch51-multus apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: backup
  annotations:
    k8s.v1.cni.cncf.io/networks: '[{"name": "storage", "ips": ["172.18.100.23/24"], "interface": "stor0"}]'
spec:
  containers:
    - name: backup
      image: nicolaka/netshoot:v0.14
      command: ["sleep", "infinity"]
EOF
kubectl -n ch51-multus exec backup -- ip -br addr
kubectl -n ch51-multus exec backup -- ping -c2 172.18.100.21
```

`make teardown CH=51` deletes the cluster; `make cluster` builds the default one
again.
