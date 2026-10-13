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
