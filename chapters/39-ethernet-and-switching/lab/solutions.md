# Chapter 39 lab: solutions

Run every command inside the lab shell (`make shell`). Port names and MAC
addresses differ every time the lab is set up; the ones below are examples.

## Task 1: Connect h3 to the switch

h3's own interface is fine:

```bash
on h3 ip -br link show dev eth0
```

It is `UP` with `LOWER_UP`: the cable is connected. So look at the switch.
Compare all port interfaces with the ones that are actually bridge ports:

```bash
ip -n sw1 -br link
bridge -n sw1 link
```

One `portN` interface is in the first list but missing from the second. To
confirm it is h3's, follow the cable: `on h3 ip link show dev eth0` prints
`eth0@ifN`, and the switch port with index `N` (the number before the colon in
`ip -n sw1 link`) is the other end. Attach it to the bridge:

```bash
ip -n sw1 link set port4 master br0
on h3 ping -c 2 10.0.3.1
```

## Task 2: Find h2's switch port

The switch learns a MAC address when that host sends a frame. Make h2 send
something, then look up h2's MAC address in the switch's table:

```bash
on h2 ping -c 1 10.0.3.1
on h2 ip -br link show dev eth0
bridge -n sw1 fdb show br br0 | grep -v permanent
```

```text
eth0@if5         UP             1a:a4:c2:5c:e7:39 <BROADCAST,MULTICAST,UP,LOWER_UP>
86:07:80:6b:c9:d1 dev port3 master br0
1a:a4:c2:5c:e7:39 dev port2 master br0
```

h2's MAC `1a:a4:c2:5c:e7:39` is behind `port2`:

```bash
echo port2 > /root/answers/39/h2-port
```

(Following the cable with `eth0@ifN`, as in Task 1, gives the same answer.)

## Task 3: Who is 10.0.3.99?

Send any packet to the address so that ARP runs, then read the ARP cache:

```bash
on h1 ping -c 1 10.0.3.99
on h1 ip neigh show 10.0.3.99
```

```text
10.0.3.99 dev eth0 lladdr 22:5e:41:0b:7c:90 REACHABLE
```

```bash
echo 22:5e:41:0b:7c:90 > /root/answers/39/mac-99
```

`arping` gets the same answer without sending an IP packet:
`on h1 arping -c 1 -I eth0 10.0.3.99`.

## Task 4: Fix the big packets

```bash
for h in h1 h2 h3 mystery; do echo "$h: $(on $h ip link show dev eth0 | grep -o 'mtu [0-9]*')"; done
```

```text
h1: mtu 1500
h2: mtu 1400
h3: mtu 1500
mystery: mtu 1500
```

h2 is the only host with a different MTU. Set it to match:

```bash
on h2 ip link set dev eth0 mtu 1500
on h1 ping -c 1 -M do -s 1472 10.0.3.2
on h2 ping -c 1 -M do -s 1472 10.0.3.1
```
