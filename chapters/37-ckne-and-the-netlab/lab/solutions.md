# Chapter 37 lab: solutions

Run every command inside the lab shell (`make shell`).

## Task 1: Find a host's address

```bash
netmap
```

```text
NAMESPACE  INTERFACE      STATE    ADDRESSES
alpha      eth0           UP       10.0.1.1/24
beta       eth0           UP       10.0.1.2/24
gamma      eth0           DOWN     10.0.1.3/24
lan        br0            UP
lan        alpha-eth0     UP
lan        beta-eth0      UP
lan        gamma-eth0     DOWN
```

Write the address without the `/24` (Chapter 40 explains that part):

```bash
echo 10.0.1.2 > /root/answers/37/beta-ip
```

## Task 2: Create a namespace

```bash
ip netns add hello
ip netns list
```

## Task 3: Run a command on another host

`gamma`'s interface is down. The command must run *inside* gamma, so prefix it with `on gamma` (or the long form `ip netns exec gamma`):

```bash
on gamma ip link set eth0 up
on gamma ping -c 2 10.0.1.1
```

Without the prefix, `ip link set eth0 up` runs in the container itself, which has no `eth0`, and fails with `Cannot find device "eth0"`.
