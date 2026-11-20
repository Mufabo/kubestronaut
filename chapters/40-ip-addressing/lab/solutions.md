# Chapter 40 lab: solutions

Run every command inside the lab shell (`make shell`).

## Task 1: Subnet math

`172.20.13.150/27`:

1. A /27 covers three full octets (24 bits) and 3 bits of the fourth octet.
2. 150 in binary: 128 + 16 + 4 + 2 = 150, so `100 10110`. The first 3 bits are network bits.
3. Network: `100 00000` = 128, so `172.20.13.128`.
4. Broadcast: `100 11111` = 128 + 31 = 159, so `172.20.13.159`.
5. Usable hosts: 5 host bits, 2⁵ − 2 = 30.

Shortcut: a /27 has 32 addresses, so subnets start at multiples of 32: 128 is
the last multiple of 32 not above 150, and the subnet ends at 128 + 31 = 159.

```bash
ipcalc 172.20.13.150/27
echo 172.20.13.128 > /root/answers/40/network
echo 172.20.13.159 > /root/answers/40/broadcast
echo 30 > /root/answers/40/hosts
```

## Task 2: Address the new host

`a` and `b` use `/24`:

```bash
on newbie ip address add 10.0.4.30/24 dev eth0
on newbie ping -c 1 10.0.4.10
on newbie ping -c 1 10.0.4.20
```

## Task 3: Fix host c

c has the right address with the wrong prefix length. Remove it and add it back with `/24`:

```bash
on c ip address del 10.0.4.200/25 dev eth0
on c ip address add 10.0.4.200/24 dev eth0
on c ip route
on c ping -c 1 10.0.4.10
```

The route now reads `10.0.4.0/24 dev eth0 ... src 10.0.4.200`, so `10.0.4.10`
is on-link for c.

Adding `10.0.4.200/24` *without* deleting the `/25` would also make the
ping work, but leave c with two copies of the same address; the task asks for
the LAN's prefix only.

## Task 4: Speak IPv6

```bash
on a ip address add fd00:4::a/64 dev eth0
on b ip address add fd00:4::b/64 dev eth0
on a ping -6 -c 2 fd00:4::b
```

If the first ping fails right after adding the addresses, wait two seconds:
new IPv6 addresses are `tentative` until duplicate address detection finishes.
