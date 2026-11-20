# Chapter 46 lab: solutions

Run every command inside the lab shell (`make shell`).

## Task 1: Find the hidden rule

```bash
on client ping -c 1 -W 1 10.10.1.1
on node iptables -L -n -v
```

iptables shows empty chains with policy ACCEPT, yet ping fails. iptables is
only one way to program netfilter. List everything with nft:

```bash
on node nft list ruleset
```

```text
table inet guard {
	chain input {
		type filter hook input priority filter; policy accept;
		ip saddr 10.10.1.0/24 icmp type echo-request counter packets 1 bytes 84 drop comment "testing, remove later"
	}
}
```

Delete the whole table (or just the rule, by its handle: `nft -a list table inet guard`
shows handles, and `nft delete rule inet guard input handle <n>` deletes one):

```bash
on node nft delete table inet guard
on client ping -c 1 10.10.1.1
```

## Task 2: A virtual IP

```bash
on node iptables -t nat -N VIP-WEB
on node iptables -t nat -A PREROUTING -d 10.96.0.10/32 -p tcp --dport 80 -j VIP-WEB
on node iptables -t nat -A VIP-WEB -p tcp -j DNAT --to-destination 10.10.2.11:80
on client curl http://10.96.0.10/
```

A plain `-A PREROUTING -d 10.96.0.10 -p tcp --dport 80 -j DNAT --to-destination 10.10.2.11:80`
works too; the separate chain prepares for Task 3 and mirrors kube-proxy's
`KUBE-SVC-*` chains. A DNAT rule that changes the port must match a protocol
(`-p tcp`) itself, or iptables refuses it.

The client needs no route for `10.96.0.10`: its default route sends the packet
to the node, where PREROUTING rewrites the destination before the node's own
routing decision.

## Task 3: Load balancing

Replace the chain's rule with two, the first matching half of the new
connections at random:

```bash
on node iptables -t nat -F VIP-WEB
on node iptables -t nat -A VIP-WEB -p tcp -m statistic --mode random --probability 0.5 -j DNAT --to-destination 10.10.2.11:80
on node iptables -t nat -A VIP-WEB -p tcp -j DNAT --to-destination 10.10.2.12:80
for i in 1 2 3 4 5 6; do on client curl -s http://10.96.0.10/; done
on node iptables -t nat -L VIP-WEB -n -v
```

The packet counters show the split. (With three backends, the probabilities
would be 1/3, then 1/2, then the rest.)

## Task 4: Backends only through the virtual IP

DNAT happens in PREROUTING, before FORWARD, so in FORWARD a packet to a backend
looks the same whether it was sent to the VIP or directly. conntrack remembers
the difference:

```bash
on node iptables -A FORWARD -d 10.10.2.0/24 -p tcp --dport 80 -m conntrack ! --ctstate DNAT -j REJECT --reject-with tcp-reset
on client curl --max-time 3 http://10.10.2.11/
on client curl http://10.96.0.10/
```

The first fails with `Could not connect`; the second works.
