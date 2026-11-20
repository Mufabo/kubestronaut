# Chapter 41 lab: solutions

Run every command inside the lab shell (`make shell`).

## Task 1: Give h1 a way out

h1 only has its connected route, so anything outside `10.5.1.0/24` is
unreachable. Its router is r1, at `10.5.1.1`:

```bash
on h1 ip route add default via 10.5.1.1
on h1 ping -c 1 10.5.0.1
```

`10.5.0.1` is one of r1's own addresses, so r1 answers it itself. No
forwarding is needed yet.

## Task 2: Reach srv

```bash
on h1 ping -c 2 -W 1 10.5.2.20
```

Nothing comes back, and nobody complains. r1 is silently dropping the packet.
Check whether it forwards at all:

```bash
on r1 sysctl net.ipv4.ip_forward
on r1 sysctl -w net.ipv4.ip_forward=1
on h1 ping -c 2 -W 1 10.5.2.20
```

Now r1 answers `Destination Net Unreachable`: it forwards, but has no route
for `10.5.2.0/24`. The next router toward that network is r2, at `10.5.0.2`:

```bash
on r1 ip route add 10.5.2.0/24 via 10.5.0.2
on h1 traceroute -n 10.5.2.20
on h1 curl http://10.5.2.20/
```

The return path already works: srv's default route points at r2, and r2 has a
route for `10.5.1.0/24` via r1.

(A default route on r1 via `10.5.0.2` instead of the specific route also
works, and it is needed in Task 3 anyway.)

## Task 3: Reach the internet

First, r1 needs to send internet-bound traffic toward r2:

```bash
on r1 ip route add default via 10.5.0.2
on h1 curl --max-time 3 http://198.51.100.1/
```

It still times out. Capture on inet (in a second lab shell) and try again:

```bash
on inet tcpdump -i eth0 -n tcp port 80
```

The SYN arrives from `10.5.1.10`, a private address. inet has no route to it,
so it never answers. The fix is not on inet (the internet never learns your
private routes) but on the edge router: translate the source address to r2's
public address on the way out of `eth2`:

```bash
on r2 iptables -t nat -A POSTROUTING -o eth2 -j MASQUERADE
on h1 curl http://198.51.100.1/
on srv curl http://198.51.100.1/
on r2 conntrack -L
```

The capture on inet now shows `198.51.100.2` as the source, and `conntrack -L`
on r2 shows each translated connection with both its original and its
translated addresses.

## Task 4: Publish srv's web server

From the internet, only r2's public address `198.51.100.2` is reachable. Tell
r2 to send connections that arrive on `eth2` for TCP port 8080 to srv's port 80:

```bash
on r2 iptables -t nat -A PREROUTING -i eth2 -p tcp --dport 8080 -j DNAT --to-destination 10.5.2.20:80
on inet curl http://198.51.100.2:8080/
```

Look at srv's side: the web server logs the client as `198.51.100.1`.
DNAT changed only the destination, and srv's reply goes back through r2 (its
default router), which reverses the translation.

```bash
tail -n 2 /var/log/netlab/srv-web.log
```
