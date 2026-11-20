# Chapter 38 lab: solutions

Run every command inside the lab shell (`make shell`).

## Task 1: Connect the hosts

Check both ends of the cable:

```bash
on client ip -br link
on server ip -br link
```

The client's `eth0` shows `NO-CARRIER` with `UP` in its flags: it is switched
on but sees nothing at the other end. The server's `eth0` has no `UP` flag at
all: it is switched off. Switch it on and test:

```bash
on server ip link set eth0 up
on client ping -c 2 10.0.2.20
```

## Task 2: Find the web server's port

```bash
on server ss -ltn
```

```text
State  Recv-Q Send-Q Local Address:Port Peer Address:Port
LISTEN 0      5          10.0.2.20:8080      0.0.0.0:*
```

```bash
echo 8080 > /root/answers/38/web-port
```

## Task 3: Capture a web request

In one lab shell, start the capture (on the server's interface; the client's works too):

```bash
on server tcpdump -i eth0 -n -w /root/answers/38/web.pcap tcp port 8080
```

In a second lab shell (`make shell` in another terminal), fetch the page:

```bash
on client curl http://10.0.2.20:8080/
```

Go back to the first shell and press Ctrl+C. Check what you captured:

```bash
tcpdump -n -r /root/answers/38/web.pcap
```

You should see a line ending in `HTTP: GET / HTTP/1.1`.

## Task 4: Read someone else's capture

```bash
tcpdump -n -r /root/answers/38/mystery.pcap
```

Find the line with `HTTP: GET`. The path is between `GET` and `HTTP/1.1`, for
example `GET /secret/page-iovbc1.html HTTP/1.1` (the name is different every
time the lab is set up). `-A` shows it too, inside the packet's text:

```bash
tcpdump -n -A -r /root/answers/38/mystery.pcap | grep GET
```

Write the path:

```bash
echo /secret/page-iovbc1.html > /root/answers/38/secret-page
```
