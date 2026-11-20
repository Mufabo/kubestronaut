# Chapter 45 lab: solutions

Run every command inside the lab shell (`make shell`). These commands run in
the container and use `ip -n <namespace>` to work on each "node" and "Pod"
without opening a shell there.

## Task 1: Wire pod2a into node2

A Pod's network is a veth pair: one end inside the Pod as `eth0`, the other
end on the node, attached to the node's bridge.

```bash
# Create the pair: veth-pod2a here, its peer directly inside pod2a as eth0
ip link add veth-pod2a type veth peer name eth0 netns pod2a
# Move the node end into node2 and attach it to the bridge
ip link set veth-pod2a netns node2
ip -n node2 link set veth-pod2a master cni0
ip -n node2 link set veth-pod2a up
# Configure the Pod end
ip -n pod2a addr add 10.9.2.10/24 dev eth0
ip -n pod2a link set eth0 up
ip -n pod2a route add default via 10.9.2.1
on pod2a ping -c 1 10.9.2.1
```

## Task 2: Routed Pod network

node1 does not know where `10.9.2.0/24` is, so it sends the packet to its
default router, core, which answers `Destination Net Unreachable`. node1 and
node2 share a LAN, so each can route the other's Pod subnet straight to the
other node:

```bash
ip -n node1 route add 10.9.2.0/24 via 192.168.9.12
ip -n node2 route add 10.9.1.0/24 via 192.168.9.11
on pod1a ping -c 1 10.9.2.10
on pod1a traceroute -n 10.9.2.10
```

```text
 1  10.9.1.1  0.334 ms  0.016 ms  0.011 ms
 2  192.168.9.12  0.633 ms  0.019 ms  0.011 ms
 3  10.9.2.10  0.023 ms  0.013 ms  0.013 ms
```

## Task 3: Overlay to node3

node3 is behind core, and core has no route for Pod subnets. A route on node1
via core would send Pod packets to core, which drops them. Instead, wrap Pod
packets in UDP packets between node addresses, which core can route:

```bash
ip -n node1 link add vxlan0 type vxlan id 42 local 192.168.9.11 remote 192.168.10.13 dstport 4789 dev eth0
ip -n node3 link add vxlan0 type vxlan id 42 local 192.168.10.13 remote 192.168.9.11 dstport 4789 dev eth0
ip -n node1 addr add 10.9.255.1/30 dev vxlan0
ip -n node3 addr add 10.9.255.2/30 dev vxlan0
ip -n node1 link set vxlan0 up
ip -n node3 link set vxlan0 up
ip -n node1 route add 10.9.3.0/24 via 10.9.255.2
ip -n node3 route add 10.9.1.0/24 via 10.9.255.1
on pod1a ping -c 1 10.9.3.10
```

A capture on core shows only node addresses on the outside:

```bash
on core tcpdump -i eth1 -n
```

```text
IP 192.168.9.11.54828 > 192.168.10.13.4789: VXLAN, flags [I] (0x08), vni 42
IP 10.9.1.10 > 10.9.3.10: ICMP echo request, id 177, seq 1, length 64
```

The `/30` addresses on the tunnel are only there to give each node a next hop
inside the tunnel. Both ends must use the same VNI (`id 42`) and port.

## Task 4: Fit through the tunnel

```bash
on pod1a ping -c 1 -M do -s 1472 10.9.3.10
```

```text
From 10.9.1.1 icmp_seq=1 Frag needed and DF set (mtu = 1450)
```

The VXLAN device has MTU 1450 (1500 minus 50 bytes of extra headers), but the
Pods still think they can send 1500 bytes. Set both ends of each tunnelled
Pod's veth pair to 1450, as CNI plugins do:

```bash
ip -n pod1a link set dev eth0 mtu 1450
ip -n node1 link set dev veth-pod1a mtu 1450
ip -n pod3a link set dev eth0 mtu 1450
ip -n node3 link set dev veth-pod3a mtu 1450
on pod1a ping -c 1 -M do -s 1422 10.9.3.10
```

(Raising the underlay MTU to 1550 on every node and on core would also work,
and some clusters do exactly that with "jumbo frames". In this lab, core
belongs to another team.)
