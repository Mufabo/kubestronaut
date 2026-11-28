# Chapter 54 lab: solutions

Try each task before reading its solution. Node commands run on a kind node:
open a shell with `docker exec -it kbook-worker bash`, or prefix one command
with `docker exec kbook-worker`.

## Part modes

### Task 1: Find shop's chain

```bash
docker exec kbook-worker iptables -t nat -S KUBE-SERVICES | grep ch54-modes/shop
```

Two rules come back, one per Service. The one whose comment says
`"ch54-modes/shop:http cluster IP"` is `shop`'s; the other belongs to
`shop-np`. Write the chain after its `-j`:

```bash
mkdir -p /tmp/kbook/ch54
docker exec kbook-worker iptables -t nat -S KUBE-SERVICES |
  sed -n 's|.*"ch54-modes/shop:http cluster IP".* -j \(KUBE-SVC-[A-Z0-9]*\).*|\1|p' > /tmp/kbook/ch54/svc-chain
cat /tmp/kbook/ch54/svc-chain
```

```text
KUBE-SVC-ZPKCQRZDOP2T2E34
```

The name is a hash of `ch54-modes/shop:http` and `tcp`, so it is the same on
every node and in every cluster.

### Task 2: Move kube-proxy to nftables

```bash
kubectl -n kube-system edit configmap kube-proxy      # mode: iptables -> mode: nftables
kubectl -n kube-system rollout restart daemonset kube-proxy
kubectl -n kube-system rollout status daemonset kube-proxy
```

Check every node, and the traffic the task names:

```bash
for n in kbook-control-plane kbook-worker kbook-worker2; do
  echo "$n: $(docker exec $n curl -s localhost:10249/proxyMode) $(docker exec $n sh -c 'iptables-save | grep -c "KUBE-S[VE][CP]-"')"
done
ip=$(kubectl -n ch54-modes get service shop -o jsonpath='{.spec.clusterIP}')
docker exec kbook-worker sh -c "nft list map ip kube-proxy service-ips | grep $ip"
for n in kbook-control-plane kbook-worker kbook-worker2; do
  docker exec $n curl -s --max-time 3 http://$ip/hostname; echo
  addr=$(kubectl get node $n -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
  docker exec ch54-outside curl -s --max-time 3 http://$addr:30054/hostname; echo
done
```

Every node prints `nftables 0`, the map has an element for the ClusterIP, and
every request gets a `shop-...` Pod name back. kube-proxy removed its
iptables-mode chains itself when it started in nftables mode. If `proxyMode`
prints nothing, kube-proxy is still starting.

### Task 3: Find shop's nftables chain

```bash
docker exec kbook-worker nft list map ip kube-proxy service-ips | grep ch54-modes/shop/
```

Again two elements: `shop`'s ClusterIP goes to the chain ending in
`ch54-modes/shop/tcp/http`, `shop-np`'s to one ending in
`ch54-modes/shop-np/tcp/` (its port has no name). Write the first:

```bash
docker exec kbook-worker nft list map ip kube-proxy service-ips |
  sed -n 's|.*goto \(service-[A-Z0-9]*-ch54-modes/shop/tcp/http\).*|\1|p' > /tmp/kbook/ch54/nft-chain
cat /tmp/kbook/ch54/nft-chain
docker exec kbook-worker nft list chain ip kube-proxy "$(cat /tmp/kbook/ch54/nft-chain)"
```

```text
service-2NZ7PM6I-ch54-modes/shop/tcp/http
```

The last command shows the chain itself: one DNAT rule that picks one of the
two `shop` Pods with `numgen random mod 2`.

## Part replace

### Task 1: Turn on the kube-proxy replacement

```bash
helm -n kube-system list                    # CHART cilium-1.20.5
helm upgrade cilium cilium --repo https://helm.cilium.io --version 1.20.5 --namespace kube-system \
  --reuse-values --set kubeProxyReplacement=true \
  --set k8sServiceHost=kbook-control-plane --set k8sServicePort=6443
kubectl -n kube-system rollout restart daemonset cilium
kubectl -n kube-system rollout status daemonset cilium
for p in $(kubectl -n kube-system get pods -l k8s-app=cilium -o name); do
  kubectl -n kube-system exec $p -c cilium-agent -- cilium-dbg status | grep KubeProxyReplacement
done
```

Every agent prints `KubeProxyReplacement:    True`. `--reuse-values` keeps
everything the profile set at install time (tunnel mode, IPAM, Hubble);
without it, they fall back to the chart's defaults. The agents read
`cilium-config` only when they start, hence the restart.

### Task 2: Remove kube-proxy

```bash
kubectl -n kube-system delete daemonset kube-proxy
kubectl -n kube-system delete configmap kube-proxy
kubectl -n kube-system get pods -l k8s-app=kube-proxy     # wait until none are left
for n in kbook-control-plane kbook-worker kbook-worker2; do
  docker exec $n sh -c 'iptables-save | grep -v KUBE | iptables-restore; ip6tables-save | grep -v KUBE | ip6tables-restore'
done
docker exec kbook-worker sh -c 'iptables-save | grep "^:KUBE"'
```

Wait until the kube-proxy Pods are gone before you clean up: a kube-proxy that
still runs writes its rules again. kube-proxy ran in iptables mode, for IPv4
and IPv6, so both need cleaning; there are no nftables tables to delete. The
cleanup also removes the kubelet's `KUBE-KUBELET-CANARY`, `KUBE-FIREWALL`, and
`KUBE-IPTABLES-HINT`; the kubelet creates them again within a minute, and
after that they are all the last command shows. Test:

```bash
kubectl -n ch54-replace exec client -- curl -s http://shop/hostname; echo
ip=$(kubectl -n ch54-replace get service shop -o jsonpath='{.spec.clusterIP}')
docker exec kbook-worker curl -s http://$ip/hostname; echo
addr=$(kubectl get node kbook-worker2 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
docker exec ch54-outside curl -s http://$addr:30054/hostname; echo
```

### Task 3: What client puts on the wire

In one terminal:

```bash
kubectl -n ch54-replace exec -it client -- tcpdump -n -i eth0 -c 1 'tcp[tcpflags] & tcp-syn != 0'
```

In a second one:

```bash
kubectl -n ch54-replace exec client -- curl -s http://shop/hostname
```

The captured line has the form `IP <client>.<port> > <address>.8080: Flags [S]`:
the SYN already goes to a `shop` Pod, port 8080, because socket LB connected
curl's socket to a backend (Step 7 of the walkthrough shows the same). Check
the address against `kubectl -n ch54-replace get pods -o wide`, and write it
with a colon before the port:

```bash
echo <address>:8080 > /tmp/kbook/ch54/wire-dst
```

Before Task 1, the same capture shows the ClusterIP and port 80.
