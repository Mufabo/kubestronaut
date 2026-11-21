# Chapter 52 lab: solutions

All commands run on your machine, in the repository folder. Addresses and
interface names change with every setup.

## Task 1: Find web's interface on its node

```bash
kubectl -n ch52-debug exec web -- cat /sys/class/net/eth0/iflink
```

The output is an interface index, for example `17`. On `web`'s node:

```bash
docker exec kbook-worker2 ip -o link | awk -F': ' '$1 == 17 {print $2}'
```

```text
lxc63f33b3cb89d@if16
```

Write the name without the `@` part:

```bash
echo lxc63f33b3cb89d > /tmp/kbook/ch52/web-veth
```

## Task 2: api refuses connections

```bash
kubectl -n ch52-debug get pods -l app=api -o wide
kubectl -n ch52-debug exec client -- nc -w 2 <api-ip> 8080 </dev/null; echo "rc=$?"
kubectl -n ch52-debug debug -it <api-pod> --image=nicolaka/netshoot:v0.14 --target=api -- ss -lntp
```

`socat` listens on `127.0.0.1:8080` only. Change its bind address in the
Deployment (`kubectl -n ch52-debug edit deployment api`, the `command`
list): `TCP-LISTEN:8080,bind=0.0.0.0,fork,reuseaddr`. Or as a patch:

```bash
kubectl -n ch52-debug patch deployment api --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/command/1","value":"TCP-LISTEN:8080,bind=0.0.0.0,fork,reuseaddr"}]'
kubectl -n ch52-debug rollout status deployment/api
kubectl -n ch52-debug exec client -- nc -w 2 <new-api-ip> 8080 </dev/null
```

## Task 3: Nothing reaches kbook-worker2

```bash
web=$(kubectl -n ch52-debug get pod web -o jsonpath='{.status.podIP}')
kubectl -n ch52-debug exec client -- curl -s --max-time 3 http://${web}:8080/hostname; echo " rc=$?"
```

Exit code 28: a timeout. Capture on both nodes while you repeat the request:

```bash
kubectl debug node/kbook-worker -it --profile=sysadmin --image=nicolaka/netshoot:v0.14 -- tcpdump -n -i eth0 -c 4 udp port 8472
kubectl debug node/kbook-worker2 -it --profile=sysadmin --image=nicolaka/netshoot:v0.14 -- tcpdump -n -i eth0 -c 4 udp port 8472
```

The SYNs leave `kbook-worker` and arrive on `kbook-worker2`, and nothing
answers. Look at `kbook-worker2`'s firewall and delete the rule:

```bash
docker exec kbook-worker2 iptables -L INPUT -n --line-numbers
docker exec kbook-worker2 iptables -D INPUT -p udp --dport 8472 -j DROP
kubectl -n ch52-debug exec client -- curl -s --max-time 3 http://${web}:8080/hostname
```

Switching Cilium to native routing would also get around the rule, but it
hides the fault instead of fixing it, and the task says tunnel mode stays.
Delete the node debug Pods afterwards (`kubectl get pods -A | grep
node-debugger`).

## Task 4: client cannot resolve Service names

```bash
kubectl -n ch52-debug exec client -- cat /etc/resolv.conf
kubectl -n ch52-debug get pod client -o jsonpath='{.spec.dnsPolicy}{"\n"}'
```

`dnsPolicy: Default` gives `client` the node's resolver. The policy cannot be
changed on a running Pod; recreate it:

```bash
kubectl -n ch52-debug get pod client -o yaml > /tmp/ch52-client.yaml
# edit: dnsPolicy: ClusterFirst (and remove the status section)
kubectl replace --force -f /tmp/ch52-client.yaml
kubectl -n ch52-debug exec client -- dig +short web.ch52-debug.svc.cluster.local
kubectl -n ch52-debug get service web
```

The address `dig` prints is the Service's ClusterIP.

`make teardown CH=52` removes the answer folder and deletes the cluster;
`make cluster` builds the default one again.
