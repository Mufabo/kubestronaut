# Chapter 53 lab: solutions

All commands run on your machine. Add `-n ch53-services` everywhere, or select the
namespace once with `kubectl config set-context --current --namespace=ch53-services`.

## Task 1: A Service for shop

```bash
kubectl -n ch53-services expose deployment shop --port=80 --target-port=8080
kubectl -n ch53-services get endpointslices -l kubernetes.io/service-name=shop
kubectl -n ch53-services exec client -- curl -s http://shop/hostname
```

`kubectl expose` takes the selector from the Deployment (`app=shop`). The
EndpointSlice lists all three Pods on port 8080.

## Task 2: Fix cart

The Service has endpoints, but connections are refused at once:

```text
curl: (7) Failed to connect to cart port 80 after 2 ms: Could not connect to server
```

Compare the Service's `targetPort` with the containers' port:

```bash
kubectl -n ch53-services describe service cart | grep -E 'TargetPort|Endpoints'
kubectl -n ch53-services get pods -l app=cart -o jsonpath='{.items[0].spec.containers[0].ports}'; echo
```

```text
TargetPort:               8080/TCP
Endpoints:                10.244.1.33:8080,10.244.2.138:8080
[{"containerPort":9090,"name":"api","protocol":"TCP"}]
```

The Pods listen on 9090, named `api`. Point the Service there, by name or by
number:

```bash
kubectl -n ch53-services patch service cart --type=json \
  -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":"api"}]'
kubectl -n ch53-services exec client -- curl -s http://cart/hostname
```

`kubectl -n ch53-services edit service cart` and changing `targetPort: 8080` to
`targetPort: api` (or `9090`) works just as well.

## Task 3: Open shop to the outside

`kubectl expose` cannot set the node port, so write the Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: shop-public
  namespace: ch53-services
spec:
  type: NodePort
  selector:
    app: shop
  ports:
    - port: 80
      targetPort: http
      nodePort: 30017
```

```bash
kubectl apply -f shop-public.yaml
for ip in $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[0].address}'); do
  docker exec ch53-outside curl -s http://$ip:30017/hostname; echo " <- $ip"
done
```

## Task 4: Sticky sessions

```yaml
apiVersion: v1
kind: Service
metadata:
  name: shop-sticky
  namespace: ch53-services
spec:
  selector:
    app: shop
  sessionAffinity: ClientIP
  ports:
    - port: 80
      targetPort: 8080
```

```bash
kubectl apply -f shop-sticky.yaml
for i in 1 2 3 4 5 6 7 8; do kubectl -n ch53-services exec client -- curl -s http://shop-sticky/hostname; echo; done
```

Or `kubectl -n ch53-services expose deployment shop --name=shop-sticky --port=80
--target-port=8080 --session-affinity=ClientIP`.

## Task 5: Every Pod by name

```bash
kubectl -n ch53-services expose deployment shop --name=shop-pods --cluster-ip=None --port=8080
kubectl -n ch53-services exec client -- dig +short shop-pods.ch53-services.svc.cluster.local
kubectl -n ch53-services get pods -l app=shop -o wide
```

The three addresses `dig` prints are the `shop` Pods' addresses.

## Task 6: A load-balancer address

Create the pool (it is cluster-scoped, so it has no namespace) and the Service:

```yaml
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: ch53-pool
spec:
  blocks:
    - cidr: 172.18.17.0/29
```

```bash
kubectl apply -f ch53-pool.yaml
kubectl -n ch53-services expose deployment shop --name=shop-lb --type=LoadBalancer --port=80 --target-port=8080
kubectl -n ch53-services get service shop-lb
```

```text
NAME      TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
shop-lb   LoadBalancer   10.96.213.168   172.18.17.1   80:32293/TCP   20s
```

Save the address and test it from `client`:

```bash
kubectl -n ch53-services get service shop-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' > /tmp/kbook/ch53/lb-ip
kubectl -n ch53-services exec client -- curl -s http://$(cat /tmp/kbook/ch53/lb-ip)/hostname
```

From `ch53-outside` the address does not answer yet: nothing announces it on
the kind network. Chapter 59 adds that.
