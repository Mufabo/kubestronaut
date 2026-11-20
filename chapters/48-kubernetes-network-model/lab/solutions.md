# Chapter 48 lab: solutions

The Pod CIDRs and node addresses change every time the cluster is built. Read
yours first and use them in place of the example values below:

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,IP:.status.addresses[0].address,PODCIDR:.spec.podCIDR
```

```text
NAME                  IP           PODCIDR
kbook-control-plane   172.18.0.3   10.244.0.0/24
kbook-worker          172.18.0.2   10.244.2.0/24
kbook-worker2         172.18.0.4   10.244.1.0/24
```

## Task 1: Find a node's Pod range

The controller manager writes each node's range into `spec.podCIDR`:

```bash
kubectl get node kbook-worker2 -o jsonpath='{.spec.podCIDR}' > /tmp/kbook/ch48/podcidr
cat /tmp/kbook/ch48/podcidr
```

## Task 2: Give the cluster a network

Write a configuration list to `/etc/cni/net.d/` on **each** node, with that
node's own Pod CIDR in the `host-local` range. Here is the one for
`kbook-worker` (Pod CIDR `10.244.2.0/24` in the example):

```bash
docker exec -it kbook-worker bash
cat > /etc/cni/net.d/10-kbook.conflist <<'JSON'
{
  "cniVersion": "1.0.0",
  "name": "kbook",
  "plugins": [
    {
      "type": "ptp",
      "ipMasq": false,
      "ipam": {
        "type": "host-local",
        "ranges": [[{"subnet": "10.244.2.0/24"}]],
        "routes": [{"dst": "0.0.0.0/0"}]
      }
    },
    {"type": "portmap", "capabilities": {"portMappings": true}}
  ]
}
JSON
jq . /etc/cni/net.d/10-kbook.conflist >/dev/null && echo valid
exit
```

Do the same on `kbook-worker2` and `kbook-control-plane` with their ranges. To do
all three from your machine in one go:

```bash
for n in kbook-control-plane kbook-worker kbook-worker2; do
  c=$(kubectl get node "$n" -o jsonpath='{.spec.podCIDR}')
  docker exec -i "$n" tee /etc/cni/net.d/10-kbook.conflist >/dev/null <<JSON
{
  "cniVersion": "1.0.0",
  "name": "kbook",
  "plugins": [
    {"type": "ptp", "ipMasq": false,
     "ipam": {"type": "host-local", "ranges": [[{"subnet": "$c"}]], "routes": [{"dst": "0.0.0.0/0"}]}},
    {"type": "portmap", "capabilities": {"portMappings": true}}
  ]
}
JSON
done
```

containerd notices the file within seconds. The nodes turn `Ready`, the
scheduler places the waiting Pods, and each gets an address from its node's
range:

```bash
kubectl get nodes
kubectl -n ch48-cni get pods -o wide
```

## Task 3: Pod to Pod across nodes

`ptp` connects each Pod only to its own node. A packet from `client` to `web`'s
address follows `kbook-worker`'s default route to the Docker network's gateway,
which knows nothing about Pod addresses:

```bash
docker exec kbook-worker ip route get 10.244.1.2
```

```text
10.244.1.2 via 172.18.0.1 dev eth0 src 172.18.0.2 uid 0
```

Add a route on each worker to the other worker's Pod CIDR, via that worker's
address, so that both directions work:

```bash
docker exec kbook-worker  ip route add 10.244.1.0/24 via 172.18.0.4
docker exec kbook-worker2 ip route add 10.244.2.0/24 via 172.18.0.2
kubectl -n ch48-cni exec client -- curl -s http://10.244.1.2:8080/clientip
```

```text
10.244.2.2:34980
```

The source `web` sees is `client`'s own Pod IP: no NAT, as the network model
requires.

## Task 4: Services and DNS

Name lookups still fail:

```text
;; no servers could be reached
```

`client` asks `10.96.0.10`, the Service address of CoreDNS. kube-proxy
translates that to a CoreDNS Pod, and in this lab those run on the control
plane, whose Pod CIDR no worker has a route to yet (and the control plane has
no routes back). Complete the mesh of routes:

```bash
docker exec kbook-worker        ip route add 10.244.0.0/24 via 172.18.0.3
docker exec kbook-worker2       ip route add 10.244.0.0/24 via 172.18.0.3
docker exec kbook-control-plane ip route add 10.244.2.0/24 via 172.18.0.2
docker exec kbook-control-plane ip route add 10.244.1.0/24 via 172.18.0.4
kubectl -n ch48-cni exec client -- dig +short web.ch48-cni.svc.cluster.local
kubectl -n ch48-cni exec client -- curl -s http://web:8080/hostname
```

```text
10.96.134.214
web
```

## Task 5: Leave the cluster

The outside server (`172.18.0.8` in the example) receives `client`'s packets,
but its replies to `10.244.2.2` go to its own default gateway, which has no
route to the Pod network. Masquerade traffic that leaves the Pod network, on
every node:

```bash
for n in kbook-control-plane kbook-worker kbook-worker2; do
  docker exec "$n" iptables -t nat -A POSTROUTING -s 10.244.0.0/16 ! -d 10.244.0.0/16 -j MASQUERADE
done
kubectl -n ch48-cni exec client -- curl -s http://172.18.0.8:8080/clientip
kubectl -n ch48-cni exec client -- curl -s http://10.244.1.2:8080/clientip
```

```text
172.18.0.2:57598
10.244.2.2:42742
```

The outside server sees `kbook-worker`'s address; `web` still sees the Pod IP.

Without `! -d 10.244.0.0/16`, the rule also rewrites traffic to Pods on other
nodes. The outside server still works, but `web` then sees `172.18.0.2`, and
Task 3 fails:

```text
172.18.0.2:57572
172.18.0.2:42726
```

What you built by hand follows the same design as kindnet, kind's default
network plugin: a veth pair per Pod, addresses from the node's `podCIDR`,
routes to the other nodes, and masquerading for traffic leaving the Pod network.
