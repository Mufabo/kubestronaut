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
unless you turn that off, which would make Traefik serve every Ingress that
names no class too.

## Task 7: the Gateway API through Traefik

Turn the provider on in the same release. `--reuse-values` keeps the two settings
from Task 6; without it, `helm upgrade` falls back to the chart's defaults and
the Service becomes a `LoadBalancer` again. `gateway.enabled=false` skips the
chart's own example Gateway, because you write one yourself:

```bash
helm upgrade traefik traefik/traefik --version 41.7.1 -n ch12-traefik --reuse-values \
  --set providers.kubernetesGateway.enabled=true --set gateway.enabled=false
kubectl -n ch12-traefik rollout status deployment/traefik
kubectl get gatewayclass traefik
```

The GatewayClass shows `ACCEPTED True` once Traefik has claimed it. Then the
Gateway and the route:

```bash
kubectl -n ch12-edge apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web-gw
spec:
  gatewayClassName: traefik
  listeners:
    - name: web
      protocol: HTTP
      port: 8000
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-route
spec:
  parentRefs:
    - name: web-gw
  hostnames:
    - gw.example.test
  rules:
    - backendRefs:
        - name: web
          port: 80
EOF
kubectl -n ch12-edge get gateway web-gw
kubectl -n ch12-edge exec client -- wget -qO- --header "Host: gw.example.test" http://traefik.ch12-traefik.svc.cluster.local
```

The Gateway shows `PROGRAMMED True`, and the request prints `hello from web`. A
rule with no `matches` matches every path. The listener port is the trap: Traefik
programs a listener on the entry point with the same port, and its HTTP entry
point listens on `8000`, not `80`. With `port: 80` the Gateway stays
`PROGRAMMED False`, and `kubectl describe gateway web-gw` says why.

## Why these checks accept any correct method

Tasks 1 to 5 read the object the API server stores: the Ingress's class, host,
path, path type and backend; the TLS Secret's type; and the Gateway's and
HTTPRoute's fields. Those checks do not run traffic, because no controller
handles their classes. Tasks 6 and 7 read the release, the Service, the classes,
and the status the controller writes, and then send a request through it. You
can create the objects with YAML or with `kubectl create ingress`.
