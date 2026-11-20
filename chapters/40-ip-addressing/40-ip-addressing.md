# Chapter 40: IP addressing

> **Exams:** CKNE · Foundations (Part V), supports D1 (Managing IPAM and Pod CIDR Allocation)
> **Difficulty:** Beginner
> **Time:** ~75 min reading, ~40 min lab
> **Lab tier:** 0 (netlab)
> **Prerequisites:** Chapter 39 (MAC addresses, switches, ARP)

## Learning objectives

After this chapter you can:

- Read an IPv4 address in dotted-decimal and in binary
- Explain what the prefix length (`/24`) means and convert it to and from a subnet mask
- Work out a subnet's network address, broadcast address, and number of usable hosts by hand
- Split a network into smaller subnets
- Recognize private, loopback, link-local, and other special address ranges
- Explain how a host decides whether a destination is on its own network
- Read and write IPv6 addresses, including the `::` shorthand
- Add and remove addresses with `ip address`

## Concepts

### What an IP address is for

MAC addresses (Chapter 39) are enough to deliver a frame across one switch.
But they have no structure: knowing the MAC address `86:07:80:6b:c9:d1` tells
you nothing about *where* that interface is. A router on the internet cannot
keep a list of every MAC address in the world.

IP addresses solve this by being **hierarchical**, like postal addresses. A
postal address has a country, a city, a street, and a house number. A post
office in another country only looks at the country to decide where to send a
letter. An IP address has two parts in the same way:

- the **network part**, which says which network the host is on, and
- the **host part**, which says which host on that network it is.

Routers only look at the network part (Chapter 41). Hosts on the same network
share the network part and differ in the host part.

### IPv4 addresses

An **IPv4 address** is a 32-bit number. Nobody wants to read 32 ones and
zeros, so it is written as four bytes in decimal, separated by dots
(**dotted-decimal** notation):

```text
10.0.4.10
```

Each of the four numbers is an **octet** (eight bits), so it ranges from 0 to
255. There are about 4.3 billion IPv4 addresses in total, which turned out to
be too few for the world. That shortage explains private addresses, NAT
(Chapter 41), and IPv6, all covered below.

### Binary in five minutes

To see where the network part ends, you need to look at an address in binary.
Each bit in an octet has a value, doubling from right to left:

| Bit value | 128 | 64 | 32 | 16 | 8 | 4 | 2 | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

An octet's value is the sum of the values of the bits that are 1. To turn a
decimal number into binary, go from left to right: if the number is at least
the bit's value, write 1 and subtract; otherwise write 0.

Take 77:

- 77 is less than 128: write **0**
- 77 is at least 64: write **1**, 77 − 64 = 13
- 13 is less than 32: **0**; less than 16: **0**
- 13 is at least 8: **1**, 13 − 8 = 5
- 5 is at least 4: **1**, 5 − 4 = 1
- 1 is less than 2: **0**
- 1 is at least 1: **1**

So 77 is `01001101`. Going back: 64 + 8 + 4 + 1 = 77.

Three values come up so often that they are worth memorizing: `11111111` = 255,
`00000000` = 0, and the "first bits set" values below, which you will use for
masks:

| Bits set from the left | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Value | 128 | 192 | 224 | 240 | 248 | 252 | 254 | 255 |

### The prefix length

Where does the network part end? The address alone does not say. It comes with
a **prefix length**, written after a slash: `10.0.4.10/24` means "the first 24
bits are the network part; the remaining 8 bits are the host part". This way of
writing addresses is called **CIDR notation** (Classless Inter-Domain Routing,
pronounced "cider").

```text
10.0.4.10/24
00001010.00000000.00000100 . 00001010
\_______ network part ___/   \ host /
        (24 bits)            (8 bits)
```

Every address that starts with the same 24 bits, from `10.0.4.0` to
`10.0.4.255`, is on the same network. That network is called a **subnet**,
and it is written with its first address and the prefix length: `10.0.4.0/24`.
"A /24" is everyday speech for a subnet with a 24-bit prefix.

### Subnet masks

Older tools and documents express the same thing as a **subnet mask**: a
32-bit value with a 1 for every network bit and a 0 for every host bit,
written in dotted decimal. A /24 is 24 ones followed by 8 zeros:

```text
11111111.11111111.11111111.00000000 = 255.255.255.0
```

| Prefix | Mask | Addresses in the subnet |
| --- | --- | --- |
| /8 | 255.0.0.0 | 16,777,216 |
| /16 | 255.255.0.0 | 65,536 |
| /20 | 255.255.240.0 | 4,096 |
| /24 | 255.255.255.0 | 256 |
| /25 | 255.255.255.128 | 128 |
| /26 | 255.255.255.192 | 64 |
| /27 | 255.255.255.224 | 32 |
| /28 | 255.255.255.240 | 16 |
| /30 | 255.255.255.252 | 4 |
| /32 | 255.255.255.255 | 1 (a single address) |

The number of addresses in a subnet is 2 to the power of the number of host
bits: a /24 has 8 host bits, so 2⁸ = 256 addresses. Every extra prefix bit
halves the subnet.

### Network, broadcast, and usable addresses

Two addresses in every subnet are reserved:

- The **network address**: all host bits 0. It names the subnet itself
  (`10.0.4.0` in `10.0.4.0/24`).
- The **broadcast address**: all host bits 1. A packet sent to it goes to every
  host on the subnet (`10.0.4.255`).

Everything in between can be given to hosts, so a subnet has 2ⁿ − 2 **usable**
addresses, where n is the number of host bits. A /24 has 254.

### Working out a subnet by hand

Here is the method, using the address `10.0.4.77/26`:

1. **Find the interesting octet.** A /26 covers the first three octets fully
   (24 bits) and 2 bits of the fourth. The fourth octet is the interesting one.
2. **Write that octet in binary.** 77 = `01 001101`. The first 2 bits are network bits.
3. **Network address:** keep the network bits, set the host bits to 0:
   `01 000000` = 64. The network is `10.0.4.64/26`.
4. **Broadcast address:** keep the network bits, set the host bits to 1:
   `01 111111` = 127. The broadcast address is `10.0.4.127`.
5. **Usable hosts:** 6 host bits, 2⁶ − 2 = 62, from `10.0.4.65` to `10.0.4.126`.

A shortcut for step 3: a /26 subnet has 64 addresses, so subnets start at
multiples of 64 (0, 64, 128, 192). 77 falls in the one that starts at 64.

The `ipcalc` tool (installed in the netlab) does this for you and shows the
binary, so you can check your work:

```bash
ipcalc 10.0.4.77/26
```

```text
Address:   10.0.4.77            00001010.00000000.00000100.01 001101
Netmask:   255.255.255.192 = 26 11111111.11111111.11111111.11 000000
Wildcard:  0.0.0.63             00000000.00000000.00000000.00 111111
=>
Network:   10.0.4.64/26         00001010.00000000.00000100.01 000000
HostMin:   10.0.4.65            00001010.00000000.00000100.01 000001
HostMax:   10.0.4.126           00001010.00000000.00000100.01 111110
Broadcast: 10.0.4.127           00001010.00000000.00000100.01 111111
Hosts/Net: 62                    Class A, Private Internet
```

The space in the binary column marks where the network part ends. Learn the
method by hand anyway: you will not always have `ipcalc`, and reading CIDR
ranges quickly matters in Kubernetes configuration.

### Splitting a network: subnetting

Taking a big network and dividing it into smaller subnets is **subnetting**.
Each extra prefix bit doubles the number of subnets and halves their size.
`10.0.4.0/24` splits into:

| Split | Subnets |
| --- | --- |
| two /25 | `10.0.4.0/25`, `10.0.4.128/25` |
| four /26 | `10.0.4.0/26`, `10.0.4.64/26`, `10.0.4.128/26`, `10.0.4.192/26` |
| eight /27 | `10.0.4.0/27`, `10.0.4.32/27`, `10.0.4.64/27`, ... `10.0.4.224/27` |

Subnets must not **overlap**: every address belongs to exactly one subnet.
`10.0.4.0/25` and `10.0.4.64/26` overlap (`10.0.4.64` to `10.0.4.127` are in
both), and overlapping ranges cause routing confusion that is very hard to debug.

> **Why this matters for Kubernetes:** this is exactly what Kubernetes **IPAM**
> (IP Address Management) does, and it is a CKNE competency. A cluster gets one
> large **Pod CIDR**, for example `10.244.0.0/16`, and each node is given a
> slice of it, for example a /24: node 1 gets `10.244.0.0/24`, node 2
> `10.244.1.0/24`, and so on. A /16 split into /24s gives 256 node subnets of
> 254 usable Pod addresses each. If the slice is too small, a node runs out of
> Pod IPs; if the cluster CIDR is too small, the cluster runs out of node slices.
> Chapter 50 configures this.

### How a host uses its prefix

The prefix length is not decoration. When a host sends a packet, it compares
the destination with its own subnet:

- **Destination inside my subnet?** It is **on-link**: the host sends the
  frame directly, after ARPing for the destination's MAC address (Chapter 39).
- **Destination outside my subnet?** It must go through a **router**
  (Chapter 41). Without a router, the host gives up with
  `Network is unreachable`.

When you add an address with a prefix, Linux automatically creates a route
that says "this subnet is directly on this interface". `ip route` shows it:

```text
10.0.4.0/24 dev eth0 proto kernel scope link src 10.0.4.10
```

Read it as: "the subnet `10.0.4.0/24` is reachable directly on `eth0`
(`scope link`); use `10.0.4.10` as my source address."

A wrong prefix length breaks this. Host c in this chapter's lab has
`10.0.4.200/25` instead of `/24`. Its route says only `10.0.4.128/25` is
on-link, so to c, host a at `10.0.4.10` is on a different network. When a
pings c, a believes c is on-link and broadcasts an ARP request for it. c
receives the request, but Linux only answers an ARP request when it could
send a packet back to the asker, and c has no route to `10.0.4.10`. So c stays
silent, a never learns c's MAC address, and the ping never leaves a. The rule
is that every host on a subnet must agree on the prefix length.

### Special address ranges

Some ranges have special meanings. The ones you will meet in this book:

| Range | Name | Meaning |
| --- | --- | --- |
| `10.0.0.0/8` | private | Free for anyone to use inside their own network |
| `172.16.0.0/12` | private | Free for anyone to use (172.16.0.0 to 172.31.255.255) |
| `192.168.0.0/16` | private | Free for anyone to use; most home networks |
| `127.0.0.0/8` | loopback | The host itself (`127.0.0.1`); never leaves the host |
| `169.254.0.0/16` | link-local | Self-assigned when no address is configured; also used by cloud metadata services (`169.254.169.254`) |
| `100.64.0.0/10` | shared (CGNAT) | Used by internet providers between customers and the internet |
| `0.0.0.0/0` | "any" | All addresses; as a route, the default route (Chapter 41) |
| `224.0.0.0/4` | multicast | Delivered to a group of interested hosts |

The three **private** ranges (defined in RFC 1918) are not reachable from the
internet, and many organizations use the same ones internally. Hosts with
private addresses reach the internet through NAT (Chapter 41), which swaps
the private source address for a public one. Every address in this book's
labs is private.

> **Why this matters for Kubernetes:** Pod and Service CIDRs are private
> ranges, and they must not overlap with each other, with the nodes' network,
> or with any network the Pods need to reach. kubeadm's defaults are a common
> example: Pods in `10.244.0.0/16` (with Flannel), Services in `10.96.0.0/12`.
> Clusters that are connected to each other (Chapter 62) need non-overlapping
> Pod CIDRs as well.

### IPv6

**IPv6** was designed to end the address shortage for good. Its addresses are
128 bits long, written as eight groups of four hexadecimal digits separated by
colons:

```text
fd00:0004:0000:0000:0000:0000:0000:000a
```

Two rules shorten them:

1. Leading zeros in a group can be dropped: `0004` becomes `4`, `000a` becomes `a`.
2. One run of consecutive all-zero groups can be replaced with `::`.

So the address above is written `fd00:4::a`. The `::` can appear only once
(otherwise you could not tell how many zero groups each one hides).

IPv6 uses the same prefix notation as IPv4: `fd00:4::a/64`. On IPv6 networks,
almost every subnet is a **/64**: 64 bits of network, 64 bits of host. That
is 2⁶⁴ addresses per subnet, so nobody counts usable hosts in IPv6. IPv6 has
no broadcast address either; it uses multicast instead. ARP is replaced by a
similar mechanism called **Neighbor Discovery**, and `ip neigh` shows its
cache just like ARP's.

The ranges you need to recognize:

| Range | Meaning |
| --- | --- |
| `::1/128` | loopback (like `127.0.0.1`) |
| `fe80::/10` | **link-local**: every IPv6 interface gives itself one automatically; valid only on that link |
| `fc00::/7` (in practice `fd00::/8`) | **unique local addresses**: IPv6's private range |
| `2000::/3` | global unicast: public internet addresses |

> **Why this matters for Kubernetes:** Kubernetes supports **dual-stack**
> clusters, where every Pod and Service gets both an IPv4 and an IPv6
> address. You configure two Pod CIDRs and two Service CIDRs, one of each
> family.

## Guided walkthrough

Start the lab and open a lab shell:

```bash
make lab CH=40
make shell
topo
```

```text
Chapter 40 lab: one LAN, intended to be 10.0.4.0/24

       a                b                c              newbie
  10.0.4.10/24     10.0.4.20/24    10.0.4.200/25     (no address)
       |eth0            |eth0           |eth0            |eth0
  +----+----------------+---------------+----------------+----+
  |                       switch "lan"                        |
  +-----------------------------------------------------------+
```

This lab has IPv6 switched on, so you will see a few extra addresses.

### Step 1: Read a host's addresses

```bash
on a ip address show dev eth0
```

```text
4: eth0@if4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 3e:00:ed:2b:85:5a brd ff:ff:ff:ff:ff:ff link-netns lan
    inet 10.0.4.10/24 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::3c00:edff:fe2b:855a/64 scope link proto kernel_ll
       valid_lft forever preferred_lft forever
```

- `inet 10.0.4.10/24`: the IPv4 address and its prefix length.
- `scope global`: an address usable to talk to other hosts (loopback addresses have `scope host`).
- `inet6 fe80::.../64 scope link`: an IPv6 link-local address, which the
  kernel created by itself as soon as the interface came up. It is built
  from the MAC address: compare `3c00:edff:fe2b:855a` with `3e:00:ed:2b:85:5a`.

`ip -br address` (brief) shows the same on one line per interface.

### Step 2: Read the connected route

```bash
on a ip route
```

```text
10.0.4.0/24 dev eth0 proto kernel scope link src 10.0.4.10
```

The kernel created this route when the address was added: the whole /24 is
reachable directly on `eth0`.

### Step 3: See a wrong prefix fail

Compare host c:

```bash
on c ip route
```

```text
10.0.4.128/25 dev eth0 proto kernel scope link src 10.0.4.200
```

c believes only `10.0.4.128` to `10.0.4.255` are on its network. Ask c to
reach a:

```bash
on c ping -c 1 10.0.4.10
```

```text
ping: connect: Network is unreachable
```

c does not even try: `10.0.4.10` is outside its subnet, and it has no router
to send it to. Now watch the other direction. In a second lab shell, capture
on c:

```bash
on c tcpdump -i eth0 -n arp or icmp
```

and in the first shell, ping c from a:

```bash
on a ping -c 1 -W 1 10.0.4.200
```

```text
12:17:34.630033 ARP, Request who-has 10.0.4.200 tell 10.0.4.10, length 28
12:17:35.639130 ARP, Request who-has 10.0.4.200 tell 10.0.4.10, length 28
12:17:36.663123 ARP, Request who-has 10.0.4.200 tell 10.0.4.10, length 28
```

a's ARP requests reach c, once a second, but c never replies: it has no route
back to `10.0.4.10`, so it will not answer. No ping is ever sent, because a
never learns c's MAC address. On a ping that fails this way, a prints
`Destination Host Unreachable` after a few seconds. Fixing c is Task 3.

### Step 4: Add and remove an address

`ip address add <address>/<prefix> dev <interface>` adds an address, and
`ip address del` removes one. An interface can have several addresses. As a
harmless experiment, give a a second address and remove it again:

```bash
on a ip address add 10.0.4.11/24 dev eth0
on a ip -br address show dev eth0
on a ip address del 10.0.4.11/24 dev eth0
```

```text
eth0@if4         UP             10.0.4.10/24 10.0.4.11/24 fe80::3c00:edff:fe2b:855a/64
```

When you delete an address, give the prefix length too, or `ip` deletes the
first matching address and warns you. Addresses added with `ip` are not
permanent: they disappear when the host restarts. Real servers store them in
configuration files (netplan, NetworkManager, systemd-networkd), which this
book does not need.

### Step 5: An IPv6 address

IPv6 addresses are added the same way:

```bash
on a ip address add fd00:4::a/64 dev eth0
on a ip -6 address show dev eth0
```

```text
4: eth0@if4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000 link-netns lan
    inet6 fd00:4::a/64 scope global tentative
       valid_lft forever preferred_lft forever
    inet6 fe80::3c00:edff:fe2b:855a/64 scope link proto kernel_ll
       valid_lft forever preferred_lft forever
```

`tentative` means the kernel is first checking that no other host on the link
already uses this address (**duplicate address detection**). After a second
or two the word disappears and the address is ready. Use `ping -6` (or
`ping` with an IPv6 address) to test IPv6. Leave this address in place: it is
part of Task 4.

## Hands-on lab

Start (or restart) the lab and open a lab shell:

```bash
make reset CH=40
make shell
```

Run all commands in the lab shell; type `make check CH=40` on your machine after each task. Answer files go in `/root/answers/40/`. Solutions: `chapters/40-ip-addressing/lab/solutions.md`.

### Task 1: Subnet math

Work out, by hand, the subnet that contains the address `172.20.13.150/27`. Then check your answers with `ipcalc`.

- File `/root/answers/40/network`: the network address (without the prefix)
- File `/root/answers/40/broadcast`: the broadcast address
- File `/root/answers/40/hosts`: the number of usable host addresses

### Task 2: Address the new host

Host `newbie` is plugged into the LAN but has no IP address. Give it one.

- `newbie`'s `eth0` has the address `10.0.4.30`, with the same prefix length as `a` and `b`
- `newbie` can ping `a` and `b`

### Task 3: Fix host c

Host `c` cannot talk to `a` or `b`. Fix it without changing its address.

- `c` keeps the address `10.0.4.200`, with the LAN's prefix length (and no other prefix)
- `c` can ping `a`, and `a` can ping `c`

### Task 4: Speak IPv6

Give hosts `a` and `b` IPv6 addresses in the unique local subnet `fd00:4::/64`.

- `a`'s `eth0` has `fd00:4::a/64`
- `b`'s `eth0` has `fd00:4::b/64`
- `a` can ping `b` over IPv6

## Exam tips

> **Exam tip:** Kubernetes configuration is full of CIDRs: `--cluster-cidr`,
> `--service-cluster-ip-range`, a node's `spec.podCIDR`, NetworkPolicy
> `ipBlock`s. Be able to tell at a glance whether an address falls inside one.
> The fastest check is the octet-boundary trick: in a /26, subnets start at
> multiples of 64; in a /20, the third octet starts at multiples of 16.

> **Exam tip:** In a NetworkPolicy, `ipBlock: {cidr: 10.0.4.10/32}` means
> exactly one address. A /32 is a single host; a /0 is everything.

## Common mistakes

- **Mismatched prefix lengths on one LAN.** Every host on a subnet must use the
  same prefix length. A host with a longer prefix cannot answer some of its
  neighbours, as host c shows.
- **Giving a host the network or broadcast address.** `10.0.4.0` and
  `10.0.4.255` are reserved in `10.0.4.0/24`. Linux may let you configure
  them, but they will not work properly as host addresses.
- **Deleting an address without its prefix.** `ip address del 10.0.4.200 dev eth0`
  deletes the first match and prints a warning; give the full `10.0.4.200/25`.
- **Overlapping CIDRs.** Two subnets that share addresses cause traffic to go
  to the wrong place. Check every new range against the existing ones.
- **Using `::` twice in an IPv6 address.** Only one run of zero groups may be
  shortened.

<!-- QUESTIONS:START -->

## End-of-chapter questions

**1.** What does the `/24` in `10.0.4.10/24` mean?

- **A.** The host has 24 neighbours
- **B.** The first 24 bits of the address are the network part; the remaining 8 are the host part
- **C.** The address is valid for 24 hours
- **D.** The last octet must be smaller than 24

**2.** Which subnet mask is the same as a /26 prefix?

- **A.** 255.255.255.0
- **B.** 255.255.255.128
- **C.** 255.255.255.192
- **D.** 255.255.255.224

**3.** What is the network address of `192.168.10.77/26`?

- **A.** 192.168.10.0
- **B.** 192.168.10.64
- **C.** 192.168.10.76
- **D.** 192.168.10.128

**4.** How many usable host addresses does a /28 subnet have?

- **A.** 16
- **B.** 14
- **C.** 28
- **D.** 30

**5.** Which pair of subnets overlaps?

- **A.** 10.0.4.0/25 and 10.0.4.128/25
- **B.** 10.0.4.0/25 and 10.0.4.64/26
- **C.** 10.0.4.0/26 and 10.0.4.64/26
- **D.** 10.0.4.0/24 and 10.0.5.0/24

**6.** Which of these addresses is a private (RFC 1918) address?

- **A.** 8.8.8.8
- **B.** 172.20.13.150
- **C.** 172.32.0.1
- **D.** 169.254.169.254

**7.** Host c has `10.0.4.200/25`; all other hosts on the switch use `/24`. Host a (`10.0.4.10`) pings c. What happens?

- **A.** The ping works normally
- **B.** a's ARP request goes unanswered
- **C.** c answers the ARP request, but drops the ping
- **D.** The switch drops the frame because the prefixes differ

**8.** A host with address `10.0.4.10/24` and no other routes runs `ping 10.0.9.1`. What does it print?

- **A.** Request timeout
- **B.** Network is unreachable
- **C.** Destination host unknown
- **D.** It sends an ARP request for 10.0.9.1

**9.** `CKNE` A cluster uses the Pod CIDR `10.244.0.0/16`, and each node gets a /24 from it. How many nodes can receive a Pod subnet?

- **A.** 16
- **B.** 24
- **C.** 256
- **D.** 65,536

**10.** What is the shortest correct way to write `fd00:0004:0000:0000:0000:0000:0000:000a`?

- **A.** fd00:4::a
- **B.** fd:4::a
- **C.** fd00:4:::a
- **D.** fd00::4::a

**11.** Every IPv6 interface has an address starting with `fe80::` even though nobody configured it. What is it?

- **A.** A public internet address
- **B.** A link-local address the interface gives itself; it is only valid on that one link
- **C.** The IPv6 version of the broadcast address
- **D.** An error

**12.** Which command gives interface eth0 the address 10.0.4.30 in a /24?

- **A.** ip link set eth0 10.0.4.30/24
- **B.** ip address add 10.0.4.30/24 dev eth0
- **C.** ip route add 10.0.4.30/24 dev eth0
- **D.** ifconfig add eth0 10.0.4.30

<details>
<summary>Answers</summary>

**1. B.** The prefix length says how many leading bits identify the network. A /24 leaves 8 host bits, so the subnet is 10.0.4.0 to 10.0.4.255.

**2. C.** 26 one-bits: three full octets (255.255.255) plus two bits in the fourth octet, 128 + 64 = 192. /25 is .128 and /27 is .224.

**3. B.** A /26 subnet has 64 addresses, so subnets start at 0, 64, 128, 192 in the last octet. 77 is in the one that starts at 64. In binary: 77 = 01 001101; keeping the first two bits gives 01 000000 = 64.

**4. B.** A /28 leaves 4 host bits: 2^4 = 16 addresses, minus the network and broadcast addresses, gives 14 usable.

**5. B.** 10.0.4.0/25 covers 10.0.4.0 to 10.0.4.127, and 10.0.4.64/26 covers 10.0.4.64 to 10.0.4.127, which is inside it. The other pairs sit side by side without sharing addresses.

**6. B.** The private ranges are 10.0.0.0/8, 172.16.0.0/12 (172.16.0.0 to 172.31.255.255), and 192.168.0.0/16. 172.32.0.1 is just outside the /12. 169.254.0.0/16 is link-local, not private, and 8.8.8.8 is a public address.

**7. B.** a believes c is on-link and broadcasts an ARP request. c receives it, but its connected route only covers 10.0.4.128/25, so it has no route back to 10.0.4.10, and Linux does not answer ARP requests from addresses it cannot reach. Without a MAC address, a never sends the ping. Switches never look at IP prefixes.

**8. B.** 10.0.9.1 is outside 10.0.4.0/24, and the host has no route (no router) for it, so the kernel refuses to send at all: Network is unreachable. ARP is only used for on-link destinations.

**9. C.** Going from /16 to /24 adds 8 bits, so the /16 splits into 2^8 = 256 subnets of /24. Each gives a node up to 254 usable Pod addresses.

**10. A.** Drop leading zeros in each group (0004 to 4, 000a to a) and replace the one run of zero groups with ::. Trailing zeros (fd00) cannot be dropped, and :: may appear only once.

**11. B.** fe80::/10 addresses are created automatically, often from the MAC address, and are used for communication on the local link only, for example by Neighbor Discovery. IPv6 has no broadcast address.

**12. B.** `ip address add <address>/<prefix> dev <interface>` adds an address. Adding it also creates the connected route for 10.0.4.0/24. ip link manages interfaces, not addresses.

</details>

<!-- QUESTIONS:END -->

## Further reading

- RFC 1918, *Address Allocation for Private Internets*
- RFC 4632, *Classless Inter-domain Routing (CIDR)*
- RFC 5952, *A Recommendation for IPv6 Address Text Representation* (how to shorten IPv6 addresses)
- `man ip-address` and `man ipcalc` in the lab shell
