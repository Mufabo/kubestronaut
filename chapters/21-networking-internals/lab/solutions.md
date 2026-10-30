# Chapter 21 lab: solutions

Try each task before reading its solution. The commands below pass
`-n ch21-net` explicitly, because the lab does not change your default namespace.

## Task 1: the pod CIDR of `kbook-worker`

```bash
kubectl get node kbook-worker -o jsonpath='{.spec.podCIDR}' > /tmp/ch21-cidr.txt
```

The control plane assigns each node its range when the node joins. The
value is in the node's spec, not in a Pod.

## Task 2: the cluster IP of `backend`

```bash
kubectl -n ch21-net get service backend -o jsonpath='{.spec.clusterIP}' > /tmp/ch21-ip.txt
```

The same address comes back from `nslookup backend` inside a Pod in the namespace.

## Task 3: the default deny

```bash
cat <<'YAML' | kubectl -n ch21-net apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes:
    - Ingress
YAML
kubectl -n ch21-net exec intruder -- wget -T 3 -qO- http://backend || echo "blocked"
```

An empty `podSelector` selects every Pod, and `Ingress` with no rules denies all
inbound traffic. The intruder is blocked, which proves that Calico enforces the
policy.

## Task 4: allow the client

```bash
cat <<'YAML' | kubectl -n ch21-net apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: client
      ports:
        - protocol: TCP
          port: 80
YAML
kubectl -n ch21-net exec client -- wget -T 3 -qO- http://backend >/dev/null && echo "client reaches backend"
```

The policy adds an allowed path. The deny from Task 3 still blocks the intruder.

## Task 5: the kube-proxy mode

```bash
kubectl -n kube-system get configmap kube-proxy -o jsonpath='{.data.config\.conf}' | sed -n 's/^mode: *"\{0,1\}\([a-z]*\)"\{0,1\}$/\1/p' > /tmp/ch21-proxy.txt
```

The mode sits in the `config.conf` key, as a line `mode: iptables` in this cluster.

## Why these checks accept any correct method

The checks read the stored objects, the Service and node fields, the ConfigMap, and
what a Pod can reach. Reaching the backend from `client` and failing from
`intruder` is a test of behaviour, so a policy that is stored but not enforced
fails the check.
