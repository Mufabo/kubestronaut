# Chapter 42 lab: solutions

Run every command inside the lab shell (`make shell`). Port numbers and the
code word are random per setup; the ones below are examples.

## Task 1: Find the hidden TCP service

```bash
on server ss -ltn
```

```text
State  Recv-Q Send-Q Local Address:Port  Peer Address:Port
LISTEN 0      5            0.0.0.0:24630      0.0.0.0:*
LISTEN 0      5          127.0.0.1:9090       0.0.0.0:*
LISTEN 0      5            0.0.0.0:8081       0.0.0.0:*
```

9090 and 8081 are the app and the old web service, so the greeter is on 24630
(`ss -ltnp` confirms: that one belongs to `socat`). Connect to it:

```bash
on client nc -w 2 10.0.6.20 24630
```

```text
tcp-a5mkal
```

```bash
echo tcp-a5mkal > /root/answers/42/greeting
```

## Task 2: Find the UDP service

```bash
on server ss -lun
```

```text
State  Recv-Q Send-Q Local Address:Port  Peer Address:Port
UNCONN 0      0            0.0.0.0:47687      0.0.0.0:*
```

UDP sockets have no LISTEN state (UDP has no connections); a bound UDP socket
shows as `UNCONN`. Try it, then write the port:

```bash
echo hi | on client nc -u -w 1 10.0.6.20 47687
echo 47687 > /root/answers/42/udp-port
```

## Task 3: Make the app reachable

```bash
on client curl http://10.0.6.20:9090/
on server ss -ltnp
```

```text
curl: (7) Failed to connect to 10.0.6.20 port 9090 after 0 ms: Could not connect to server
LISTEN 0      5          127.0.0.1:9090       0.0.0.0:*    users:(("python3",pid=32,fd=3))
```

The app listens on `127.0.0.1`, the loopback address, so only programs on the
server itself can reach it. The client's SYN arrives at `10.0.6.20:9090`, where
nothing listens, and the kernel answers with a reset: connection refused.

Stop the app (the PID is in the `ss -p` output) and start it again listening
on all addresses. `nohup` and `&` keep it running in the background after you
close the shell:

```bash
kill 32
on server nohup python3 -m http.server 9090 --directory /srv/app > /tmp/app.log 2>&1 &
on server ss -ltn 'sport = :9090'
on client curl http://10.0.6.20:9090/
```

`python3 -m http.server` listens on all addresses (`0.0.0.0`) unless told
otherwise with `--bind`.

## Task 4: Refuse instead of hanging

```bash
on client curl --max-time 5 http://10.0.6.20:8081/
on server iptables -L INPUT -n -v --line-numbers
```

```text
curl: (28) Connection timed out after 5002 milliseconds
num   pkts bytes target     prot opt in     out     source               destination
1        5   300 DROP       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:8081
```

A DROP rule throws the SYN away, so the client keeps retrying until it gives
up. Replace rule 1 with a REJECT that answers with a TCP reset:

```bash
on server iptables -R INPUT 1 -p tcp --dport 8081 -j REJECT --reject-with tcp-reset
on client curl http://10.0.6.20:8081/
```

```text
curl: (7) Failed to connect to 10.0.6.20 port 8081 after 0 ms: Could not connect to server
```

Stopping the old service *and* deleting the DROP rule
(`on server iptables -D INPUT 1`) is also a correct answer: with nothing
listening on 8081, the kernel itself answers with a reset.
