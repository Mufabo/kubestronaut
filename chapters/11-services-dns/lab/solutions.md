# Chapter 11 lab: solutions

Try each task before reading its solution. The commands below assume `kubectl`
defaults to `ch11-svc` (run `make use-namespace CH=11` once). Otherwise, add
`-n ch11-svc` to every command.

## Task 1: `web`, a ClusterIP Service

```bash
kubectl expose deployment web --name=web --port=80 --target-port=80
kubectl get endpointslices -l kubernetes.io/service-name=web
```

`expose` copies the Deployment's labels into the selector. The EndpointSlice
lists the two `web` Pod IPs once they are ready.

## Task 2: `web-np`, a NodePort Service on 30080

```bash
kubectl expose deployment web --name=web-np --type=NodePort --port=80 --target-port=80
kubectl patch svc web-np -p '{"spec":{"ports":[{"port":80,"targetPort":80,"nodePort":30080}]}}'
kubectl get svc web-np
```

Without the patch, Kubernetes picks a node port from the range 30000 to 32767.
The patch sets the one the task asks for.

## Task 3: `web-headless`, a Service with no cluster IP

```bash
kubectl expose deployment web --name=web-headless --cluster-ip=None --port=80 --target-port=80
kubectl exec dns-client -- nslookup web-headless
```

The lookup returns one address per `web` Pod. The `NXDOMAIN` lines that
`nslookup` prints for other search domains are normal.

## Task 4: `legacy`, an ExternalName Service

```bash
kubectl create service externalname legacy --external-name=db.example.internal
kubectl exec dns-client -- nslookup legacy.ch11-svc.svc.cluster.local
```

The lookup answers with `canonical name = db.example.internal`.

## Task 5: fix the `api` Service

The selector is `app=api-old`, but the Pods are labeled `app=api`.

```bash
kubectl patch svc api -p '{"spec":{"selector":{"app":"api"}}}'
kubectl get endpointslices -l kubernetes.io/service-name=api
```

The patch changes the value of the existing `app` key. Deleting and recreating
the Service also works.

## Why these checks accept any correct method

Each check reads the outcome: the Service's type and ports, the EndpointSlices
(the Pod IPs that are ready), and the answers `nslookup` gives from the
`dns-client` Pod. You can create the Services with YAML, `expose`, or
`kubectl create service`. The checks do not care.
