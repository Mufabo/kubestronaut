# Chapter 47 lab: solutions

Run every command inside the lab shell (`make shell`). Each task follows the
method from the chapter: observe the symptom, find the layer, test one
hypothesis, fix one thing, check again.

## Task 1: Names do not resolve (layer 2)

```bash
on laptop curl http://app.corp.internal:8080/
on laptop dig app.corp.internal
```

```text
curl: (28) Resolving timed out after 5000 milliseconds
;; communications error to 10.11.2.53#53: timed out
```

The resolver itself is unreachable. Work up from the bottom along the path:

```bash
on laptop ping -c 1 10.11.1.1      # the laptop's router: fine
on laptop ping -c 1 10.11.2.1      # the router's dc side: fine
on laptop ping -c 1 10.11.2.53     # the DNS server: nothing
on r1 ip neigh
```

```text
10.11.2.53 dev eth1 FAILED
```

r1 cannot even resolve the DNS server's MAC address: a layer 2 problem on the
dc LAN. The switch shows why:

```bash
bridge -n dc link
ip -n dc -br link
```

`dns-eth0` exists and is up, but it is not a port of `br0`:

```bash
ip -n dc link set dns-eth0 master br0
on laptop dig +short app.corp.internal
```

## Task 2: The wrong address (layer 7)

```bash
on laptop dig +short app.corp.internal
on app ip -br addr show dev eth0
```

```text
10.11.2.81
eth0@if10        UP             10.11.2.80/24
```

DNS points at `.81`, but the app is `.80`. Fix the zone data and reload:

```bash
sed -i 's/^10.11.2.81 /10.11.2.80 /' /etc/dns/hosts.corp
pkill -HUP dnsmasq
on laptop dig +short app.corp.internal
```

## Task 3: No reply from the app (layer 3)

```bash
on laptop ping -c 2 -W 1 10.11.2.80
```

Silence. In a second shell, capture on the app:

```bash
on app tcpdump -i eth0 -n icmp
```

```text
12:54:58.118828 IP 10.11.1.10 > 10.11.2.80: ICMP echo request, id 185, seq 1, length 64
```

Requests arrive, no replies leave. The app has no route back to the office:

```bash
on app ip route
on app ip route add default via 10.11.2.1
on laptop ping -c 1 10.11.2.80
```

## Task 4: Connections time out (layer 4, a filter)

```bash
on laptop curl --max-time 3 http://10.11.2.80:8080/
on r1 iptables -L FORWARD -n -v --line-numbers
```

```text
curl: (28) Connection timed out after 3002 milliseconds
num   pkts bytes target     prot opt in     out     source               destination
1       11   660 DROP       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:8080
```

Ping works but TCP times out: a filter. The rule's packet counter goes up with
every attempt. Delete it:

```bash
on r1 iptables -D FORWARD 1
```

## Task 5: Connection refused (layer 4, the listener)

```bash
on laptop curl http://app.corp.internal:8080/
on app ss -ltnp
```

```text
curl: (7) Failed to connect to app.corp.internal port 8080 after 0 ms: Could not connect to server
LISTEN 0      5          127.0.0.1:8080      0.0.0.0:*    users:(("python3",pid=73,fd=3))
```

The app listens only on loopback. Restart it on all addresses:

```bash
kill 73
on app nohup python3 -m http.server 8080 --directory /srv/app > /tmp/app.log 2>&1 &
on laptop curl http://app.corp.internal:8080/
```

```text
hello from app
```
