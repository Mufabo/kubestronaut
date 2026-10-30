# Chapter 12 lab: solutions

Try each task before reading its solution. The commands below assume `kubectl`
defaults to `ch12-edge` (run `make use-namespace CH=12` once). Otherwise, add
`-n ch12-edge` to every command.

## Task 1: the `shop` Ingress

```bash
kubectl create ingress shop --class=nginx --rule='shop.example.test/*=shop:80'
kubectl get ingress shop -o yaml
```

The `*` after the path makes the path type `Prefix`. Without it the command
writes `Exact`, which is not what the task asks for.

## Task 2: the `docs` Ingress over TLS

First the certificate and the Secret. The Secret type must be `kubernetes.io/tls`:

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=docs.example.test" -keyout tls.key -out tls.crt
kubectl create secret tls docs-tls --cert=tls.crt --key=tls.key
```

Then the Ingress. The TLS block is not part of `kubectl create ingress`, so
write the YAML:

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: docs
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - docs.example.test
      secretName: docs-tls
  rules:
    - host: docs.example.test
      http:
        paths:
          - path: /docs
            pathType: Prefix
            backend:
              service:
                name: docs
                port:
                  number: 80
YAML
```

Delete the local `tls.key` and `tls.crt` files afterwards.

## Task 3: the `api` Ingress on port 8080

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api
spec:
  ingressClassName: nginx
  rules:
    - host: api.example.test
      http:
        paths:
          - path: /v1
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 8080
YAML
```

The backend uses the Service's port, 8080. The container listens on 80, which is
the Service's `targetPort`, and an Ingress never names it.

## Task 4: the `edge` Gateway

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: edge
spec:
  gatewayClassName: ch12-edge-class
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "*.example.test"
YAML
```

The GatewayClass `ch12-edge-class` was created by the lab's setup. Its
`Accepted` condition stays `Unknown`, because no controller runs in this cluster.

## Task 5: the `shop-route` HTTPRoute

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: shop-route
spec:
  parentRefs:
    - name: edge
  hostnames:
    - shop.example.test
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: shop
          port: 80
YAML
```

## Task 6: Traefik, and `web` through it

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update traefik
helm show values traefik/traefik --version 41.7.1 | less     # find service.spec.type and ingressClass
helm install traefik traefik/traefik --version 41.7.1 \
  --namespace ch12-traefik --create-namespace \
  --set service.spec.type=ClusterIP --set ingressClass.isDefaultClass=false
kubectl -n ch12-traefik rollout status deployment/traefik
helm get values traefik -n ch12-traefik
kubectl -n ch12-traefik get service traefik
kubectl get ingressclass traefik -o yaml | grep is-default-class

kubectl -n ch12-edge create ingress web --class=traefik --rule="web.example.test/*=web:80"
kubectl -n ch12-edge exec client -- wget -qO- --header "Host: web.example.test" http://traefik.ch12-traefik.svc.cluster.local
```

The last command prints `hello from web`. A request without the `Host` header, or
with another host, gets Traefik's own 404: the controller routes by host, as the
Ingress rule says.

Two traps. The chart's Service type is `service.spec.type`; `--set
service.type=ClusterIP` is accepted and ignored, so the Service stays
`LoadBalancer`. And the chart marks its IngressClass as the cluster default
unless you turn that off, which would make Traefik serve the Ingress `api` from
Task 3 too, because it names no class.

## Why these checks accept any correct method

Each check reads the object the API server stores: the Ingress's class, host,
path, path type and backend; the TLS Secret's type; and the Gateway's and
HTTPRoute's fields. The checks do not run traffic, because the lab has no
controller. You can create the objects with YAML or with `kubectl create ingress`.
