# Chapter 36 lab: solutions

Try each task before reading its solution. Every command passes `-n ch36-shop`.

## Task 1: default deny, and DNS allowed

```bash
kubectl -n ch36-shop apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes: ["Ingress", "Egress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
spec:
  podSelector: {}
  policyTypes: ["Egress"]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
YAML
```

The empty `podSelector` selects every Pod in the Namespace. The `allow-dns` policy
restores the one egress flow that every Pod needs. Without it, `stranger` cannot resolve
`api`. Test with `kubectl -n ch36-shop exec stranger -- wget -T 3 -O- http://api:8080/`,
which times out.

## Task 2: frontend to api

```bash
kubectl -n ch36-shop apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-to-api
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes: ["Egress"]
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: api
      ports:
        - port: 8080
          protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-from-frontend
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - port: 8080
          protocol: TCP
YAML
```

The sender's egress and the receiver's ingress are two separate objects. The `stranger`
Pod matches neither rule, so the default deny keeps it blocked.

## Task 3: api to db

The same pattern, one tier down: an egress rule on `app=api` to `app=db` on port 5432,
and an ingress rule on `app=db` from `app=api` on port 5432 (`api-to-db` and `db-from-api`).

## Task 4: a TLS Secret

```bash
kubectl -n ch36-shop create secret tls api-tls --cert=/tmp/ch36/api.crt --key=/tmp/ch36/api.key
```

The `tls` subcommand sets the type to `kubernetes.io/tls`, and stores the two files under
`tls.crt` and `tls.key`. Check the type with
`kubectl -n ch36-shop get secret api-tls -o jsonpath='{.type}'`.

## Clean up

`make teardown CH=36` removes the Namespace, the policies, the Secret, and the certificate
files in `/tmp/ch36`.

## Part mesh: mutual TLS with Istio

### Task 1: put the shop in the mesh

```bash
kubectl label namespace ch36-mesh istio-injection=enabled
kubectl -n ch36-mesh rollout restart deployment api client other
kubectl -n ch36-mesh rollout status deployment api
kubectl -n ch36-mesh get pods -o custom-columns=NAME:.metadata.name,INIT:.spec.initContainers[*].name,CONTAINERS:.spec.containers[*].name
```

The label affects only Pods created from now on, which is why the Deployments must
roll out new Pods. Each new Pod lists `istio-init` and `istio-proxy` among its init
containers: the sidecar runs as a native sidecar, an init container that keeps running.

### Task 2: require mutual TLS

```bash
kubectl apply -f - <<'EOF2'
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: ch36-mesh
spec:
  mtls:
    mode: STRICT
EOF2
kubectl -n ch36-mesh exec deploy/client -c client -- wget -qO- -T 3 http://api.ch36-mesh:8088          # ok
kubectl -n ch36-outside exec deploy/outsider -- wget -qO- -T 3 http://api.ch36-mesh:8088           # Connection reset by peer
```

The name `default` and the missing `selector` make it apply to the whole Namespace.
Before Task 1 is done, the same policy would cut off `client` too: STRICT needs a
sidecar on both ends.

### Task 3: only the client may call the api

```bash
kubectl apply -f - <<'EOF2'
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-allow
  namespace: ch36-mesh
spec:
  selector:
    matchLabels:
      app: api
  action: ALLOW
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/ch36-mesh/sa/caller"]
EOF2
kubectl -n ch36-mesh exec deploy/client -c client -- wget -qO- -T 3 http://api.ch36-mesh:8088         # ok
kubectl -n ch36-mesh exec deploy/other -c other -- wget -qO- -T 3 http://api.ch36-mesh:8088           # 403 Forbidden
```

An ALLOW policy that selects a workload denies everything it does not allow, so `other`,
whose identity is `cluster.local/ns/ch36-mesh/sa/default`, gets HTTP 403 from the `api`'s
sidecar. The principal is the caller's ServiceAccount, proved by its mTLS certificate,
not its IP address.

`make teardown CH=36 PART=mesh` removes both Namespaces and uninstalls Istio
(`istioctl uninstall --purge`, then the `istio-system` Namespace).
