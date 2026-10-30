# Chapter 26 lab: solutions

Try each task before reading its solution. The commands below pass
`-n ch26-broken` explicitly, because the lab does not change your default namespace.
Each task has one fault, and the events, the endpoints, the policy and the name lookup
each point at one of them.

## Task 1: the image tag

```bash
kubectl -n ch26-broken describe pod -l app=api | sed -n '/Events:/,$p'
kubectl -n ch26-broken set image deployment/api api=nginx:1.27
kubectl -n ch26-broken rollout status deployment/api
```

The events name `nginx:1.27-typo`, which does not exist. The fix is the tag.

## Task 2: the selector

```bash
kubectl -n ch26-broken get endpointslices -l kubernetes.io/service-name=web
kubectl -n ch26-broken get service web -o jsonpath='{.spec.selector}{"\n"}'
kubectl -n ch26-broken patch service web -p '{"spec":{"selector":{"app":"web"}}}'
```

The endpoint list is empty, because the selector asks for `app=wbe`.

## Task 3: the target port

```bash
kubectl -n ch26-broken get service app -o jsonpath='{.spec.ports[0].targetPort}{"\n"}'
kubectl -n ch26-broken patch service app -p '{"spec":{"ports":[{"port":80,"targetPort":8080}]}}'
```

The application listens on 8080, which the Deployment's `containerPort` shows. The
endpoints were already correct, so only the port needed to change.

## Task 4: the policy

```bash
kubectl -n ch26-broken describe networkpolicy lock
cat <<'YAML' | kubectl -n ch26-broken apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: lock
spec:
  podSelector:
    matchLabels:
      app: app
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: client
      ports:
        - protocol: TCP
          port: 8080
YAML
```

The policy admitted `role=other`, while the client is `role=client`. Applying the
corrected policy replaces the old one, because it has the same name.

## Task 5: the nameserver

```bash
kubectl -n ch26-broken exec resolver -- cat /etc/resolv.conf
kubectl -n kube-system get service kube-dns -o jsonpath='{.spec.clusterIP}{"\n"}'
```

The Pod's `dnsConfig` names `10.0.0.1`, which does not answer. `dnsConfig` cannot be
changed on a running Pod, so the Pod is deleted and created again with the cluster's DNS
service address. The solve does that with the address from `kube-dns`.

## Why these checks accept any correct method

Each check reads an outcome: the Deployment's image and readiness, the Service's
endpoints and target port, a client's request to the application's Pod IP, and a
name lookup from inside the Pod. You can fix each fault with `kubectl patch`, `edit`,
or a manifest, and the checks do not care which.
