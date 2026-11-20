# Chapter 43 lab: solutions

Run every command inside the lab shell (`make shell`).

## Task 1: Point the client at the DNS server

The client's resolver configuration is empty, so it has no DNS server to ask:

```bash
on client cat /etc/resolv.conf
on client dig web.lab.internal
```

`dig` reports `no servers could be reached`. For a network namespace,
`ip netns exec` (and so `on`) uses `/etc/netns/<name>/resolv.conf` as
`/etc/resolv.conf`. Edit that file from the container:

```bash
echo 'nameserver 10.0.7.53' > /etc/netns/client/resolv.conf
on client dig +short web.lab.internal
```

(Task 3 adds a second line to the same file; you can write both now.)

## Task 2: Add a record

```bash
on client dig @10.0.7.53 api.lab.internal
```

`status: NXDOMAIN`: the name does not exist. The zone's address records are in
`/etc/dns/hosts.lab`. Add one, then send dnsmasq the HUP signal, which makes it
reread the file without restarting:

```bash
echo '10.0.7.81   api.lab.internal' >> /etc/dns/hosts.lab
pkill -HUP dnsmasq
on client dig @10.0.7.53 +short api.lab.internal
```

## Task 3: Short names

```bash
printf 'nameserver 10.0.7.53\nsearch lab.internal\n' > /etc/netns/client/resolv.conf
on client getent hosts web
on client curl http://web/
```

With `search lab.internal`, the resolver tries `web.lab.internal` when you ask
for `web`. `dig` ignores the search list unless you add `+search`.

## Task 4: Reverse lookup

```bash
on client dig -x 10.0.7.99 +short
```

```text
host-k3x9q.lab.internal.
```

Write the name without the trailing dot (the name is random per setup):

```bash
echo host-k3x9q.lab.internal > /root/answers/43/mystery-name
```
