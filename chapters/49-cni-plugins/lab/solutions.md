# Chapter 49 lab: solutions

All commands run on your machine, in the repository folder. Node addresses and
Pod CIDRs change every time the cluster is built; read yours with:

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,IP:.status.addresses[0].address,PODCIDR:.spec.podCIDR
```

## Task 1: Install Cilium

```bash
helm install cilium cilium --repo https://helm.cilium.io --version 1.20.5 \
  --namespace kube-system --set ipam.mode=kubernetes
cilium status --wait          # or: kubectl -n kube-system rollout status daemonset/cilium
kubectl get nodes
kubectl -n ch49-cni get pods -o wide
```

The Pods start as soon as their nodes have a network, and their addresses are
in their nodes' Pod CIDRs. If you installed without `ipam.mode=kubernetes`
first, the Pods got addresses from `10.0.0.0/8`. Fix the mode, restart the
agents, then recreate the Pods (they are bare Pods, so save and reapply them):

```bash
helm upgrade cilium cilium --repo https://helm.cilium.io --version 1.20.5 \
  --namespace kube-system --reuse-values --set ipam.mode=kubernetes
kubectl -n kube-system rollout restart daemonset/cilium
kubectl -n ch49-cni get pods -o yaml > /tmp/ch49-pods.yaml
kubectl -n ch49-cni replace --force -f /tmp/ch49-pods.yaml
```

## Task 2: Which configuration does the node use?

```bash
docker exec kbook-worker2 ls /etc/cni/net.d
docker exec kbook-worker2 cat /etc/cni/net.d/05-cilium.conflist
echo /etc/cni/net.d/05-cilium.conflist > /tmp/kbook/ch49/cni-conf
echo cilium-cni > /tmp/kbook/ch49/cni-plugin
```

The runtime uses the first file in name order; with Cilium (which renames
other plugins' files by default) it is the only one. Its plugin `type` is the
binary name in `/opt/cni/bin`.

## Task 3: Native routing

```bash
helm upgrade cilium cilium --repo https://helm.cilium.io --version 1.20.5 \
  --namespace kube-system --reuse-values \
  --set routingMode=native --set autoDirectNodeRoutes=true --set ipv4NativeRoutingCIDR=10.244.0.0/16
kubectl -n kube-system rollout restart daemonset/cilium
kubectl -n kube-system rollout status daemonset/cilium
docker exec kbook-worker ip route | grep 10.244
```

```text
10.244.0.0/24 via 172.18.0.4 dev eth0 proto kernel
10.244.1.0/24 via 10.244.1.131 dev cilium_host proto kernel src 10.244.1.131
10.244.1.131 dev cilium_host proto kernel scope link
10.244.2.0/24 via 172.18.0.2 dev eth0 proto kernel
```

Without the restart the ConfigMap changes, but the routes do not. Test:

```bash
web=$(kubectl -n ch49-cni get pod web -o jsonpath='{.status.podIP}')
kubectl -n ch49-cni exec client -- curl -s http://${web}:8080/clientip
kubectl -n ch49-cni get pod client -o jsonpath='{.status.podIP}'; echo
```

The address before the colon matches `client`'s Pod IP.

## Task 4: A lower MTU

```bash
helm upgrade cilium cilium --repo https://helm.cilium.io --version 1.20.5 \
  --namespace kube-system --reuse-values --set MTU=1400
kubectl -n kube-system rollout restart daemonset/cilium
kubectl -n kube-system rollout status daemonset/cilium
kubectl -n ch49-cni exec client -- cat /sys/class/net/eth0/mtu
kubectl -n ch49-cni exec web -- cat /sys/class/net/eth0/mtu
```

Both print `1400`. Running Pods are updated when the agents restart; new Pods
get it from the start.

`make teardown CH=49` removes the answer folder and deletes the cluster; `make
cluster` builds the default one again.
