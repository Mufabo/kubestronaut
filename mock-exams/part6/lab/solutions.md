# Part VI simulator: solutions

Read these after you have scored. Every question starts with
`kubectl config use-context p6-a`. Addresses and names change with every
setup.

## Question 1 | The node's CNI configuration

```bash
docker exec kbook-worker2 ls /etc/cni/net.d
docker exec kbook-worker2 cat /etc/cni/net.d/00-multus.conf
docker exec kbook-worker2 cat /etc/cni/net.d/05-cilium.conflist
echo /etc/cni/net.d/00-multus.conf > /tmp/kbook/part6/1/conf
echo cilium-cni > /tmp/kbook/part6/1/cluster-network
```

The runtime uses the first file in name order, Multus's. Its `clusterNetwork`
(`/host/etc/cni/net.d/05-cilium.conflist`, as the Multus Pod sees the node's
filesystem) names Cilium's file, whose plugin type is `cilium-cni` (Chapters 49
and 51).

## Question 2 | Where Pod addresses come from

```bash
docker exec kbook-control-plane grep cluster-cidr /etc/kubernetes/manifests/kube-controller-manager.yaml
cilium config view | grep '^ipam '      # or: kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.ipam}'
kubectl -n p6-core get pod probe -o wide
kubectl get ciliumpodippools -o custom-columns=NAME:.metadata.name,CIDRS:.spec.ipv4.cidrs
echo 10.244.0.0/16 > /tmp/kbook/part6/2/cluster-cidr
echo multi-pool > /tmp/kbook/part6/2/ipam
echo default > /tmp/kbook/part6/2/probe-pool
```

`probe`'s namespace has no pool annotation, so its address comes from
`default` (`10.10.0.0/16`), not from the cluster CIDR (Chapter 50).

## Question 3 | A namespace without addresses

```bash
kubectl -n p6-red describe pod <a-web-pod> | grep FailedCreatePodSandBox
kubectl get namespace p6-red -o jsonpath='{.metadata.annotations}'
kubectl apply -f - <<'EOF'
apiVersion: cilium.io/v2alpha1
kind: CiliumPodIPPool
metadata:
  name: red
spec:
  ipv4:
    cidrs: ["10.21.0.0/16"]
    maskSize: 27
EOF
kubectl -n p6-red get pods -o wide
```

The waiting Pods retry on their own; after a long wait they may be in a back-off
of a few minutes. `kubectl -n p6-red rollout restart deployment/web` makes new
ones at once.

## Question 4 | Not enough addresses

```bash
kubectl -n p6-batch describe pod <a-waiting-pod> | grep FailedCreatePodSandBox   # all CIDR ranges are exhausted
kubectl patch ciliumpodippool small --type=merge \
  -p '{"spec":{"ipv4":{"cidrs":["10.31.0.0/27","10.31.1.0/26"]}}}'
kubectl -n p6-batch rollout status deployment/worker
```

## Question 5 | A second interface

```bash
kubectl -n p6-fabric apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: sensor
  annotations:
    k8s.v1.cni.cncf.io/networks: '[{"name": "fabric", "ips": ["172.18.110.5/24"], "interface": "fab0"}]'
spec:
  nodeSelector: {kubernetes.io/hostname: kbook-worker2}
  containers:
    - name: sensor
      image: nicolaka/netshoot:v0.14
      command: ["sleep", "infinity"]
EOF
kubectl -n p6-fabric exec sensor -- ip -br addr show fab0
kubectl -n p6-fabric exec sensor -- ping -c2 172.18.110.4
```

## Question 6 | cart refuses connections

```bash
kubectl -n p6-shop get pods -o wide
kubectl -n p6-shop debug -it <cart-pod> --image=nicolaka/netshoot:v0.14 --target=cart -- ss -lnt
kubectl -n p6-shop patch deployment cart --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/command/1","value":"TCP-LISTEN:9000,bind=0.0.0.0,fork,reuseaddr"}]'
kubectl -n p6-core exec probe -- nc -w 2 <new-cart-ip> 9000 </dev/null
```

`socat` listened on `127.0.0.1:9000` only (Chapter 52).

## Question 7 | Traffic to one node is lost

```bash
echo=$(kubectl -n p6-core get pod echo -o jsonpath='{.status.podIP}')
kubectl -n p6-core exec probe -- curl -s --max-time 3 http://${echo}:8080/hostname; echo " rc=$?"
kubectl debug node/kbook-worker2 -it --profile=sysadmin --image=nicolaka/netshoot:v0.14 -- \
  tcpdump -n -i eth0 -c 4 host ${echo} and port 8080
docker exec kbook-worker2 iptables -L FORWARD -n -v --line-numbers
docker exec kbook-worker2 iptables -D FORWARD -s 10.0.0.0/8 -d 10.0.0.0/8 -i eth0 -j DROP
```

With native routing the SYN arrives on `kbook-worker2`'s `eth0` with Pod
addresses and must be forwarded to `echo`'s interface; the first `FORWARD` rule
drops exactly that, and its packet counter grows with every attempt.

## Question 8 | A Pod that cannot resolve names

```bash
kubectl -n p6-core exec lookup -- cat /etc/resolv.conf     # nameserver 10.96.0.99: nothing answers there
kubectl -n p6-core get pod lookup -o yaml > /tmp/lookup.yaml
# edit: dnsPolicy: ClusterFirst, delete the dnsConfig section and the status section
kubectl replace --force -f /tmp/lookup.yaml
kubectl -n p6-core exec lookup -- dig +short echo.p6-core.svc.cluster.local
```

`dnsPolicy: None` uses only `dnsConfig`, which pointed at an address where no
DNS server runs (Chapter 52).
