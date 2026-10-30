# Mock exam CKAD, set 2: solutions

Read these only after `make mock-score EXAM=ckad2`. Each entry shows one way to
answer the question; the checks accept any method that leaves the same result. The
chapter in brackets teaches the topic.

## Question 1: an image that runs as a user (Chapter 16)

Add to the Dockerfile:

```dockerfile
USER 1000
EXPOSE 8080
```

```bash
cd /tmp/kbook/ckad2/1/app
docker build -t ckad2-api:1.1 .
docker save -o /tmp/kbook/ckad2/1/ckad2-api.tar ckad2-api:1.1
docker image inspect ckad2-api:1.1 --format '{{.Config.User}} {{.Config.ExposedPorts}}'
```

`EXPOSE` documents the port in the image's configuration; it does not publish it.
`USER` makes every process in the container run as that user, unless the Pod's
`securityContext` overrides it.

## Question 2: an init container fills the web root (Chapter 09)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web-cache
  namespace: ckad2-design
spec:
  volumes:
    - name: html
      emptyDir: {}
  initContainers:
    - name: fetch
      image: busybox:1.36
      command: ["sh", "-c", "echo 'ckad2 ready' > /html/index.html"]
      volumeMounts:
        - name: html
          mountPath: /html
  containers:
    - name: web
      image: nginx:1.27
      volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
```

The volume can be mounted at different paths in each container; the files are the same.

## Question 3: a CronJob with limits (Chapter 08)

```bash
kubectl -n ckad2-design create cronjob cleanup --image=busybox:1.36 --schedule='*/15 * * * *' \
  --dry-run=client -o yaml -- sh -c 'echo cleaning' > cleanup.yaml
```

Add to `spec`: `successfulJobsHistoryLimit: 2`, `failedJobsHistoryLimit: 1`,
`startingDeadlineSeconds: 60`; to `jobTemplate.spec`: `activeDeadlineSeconds: 30`;
and set the Pod template's `restartPolicy: Never` (the generator writes `OnFailure`).
Then `kubectl apply -f cleanup.yaml`.

`startingDeadlineSeconds` limits how late a run may start; `activeDeadlineSeconds`
limits how long a Job may run once started.

## Question 4: a StatefulSet with a claim per replica (Chapter 13)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kv
  namespace: ckad2-design
spec:
  clusterIP: None
  selector:
    app: kv
  ports:
    - port: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kv
  namespace: ckad2-design
spec:
  serviceName: kv
  replicas: 2
  selector:
    matchLabels:
      app: kv
  template:
    metadata:
      labels:
        app: kv
    spec:
      containers:
        - name: kv
          image: nginx:1.27
          volumeMounts:
            - name: data
              mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 64Mi
```

The claims are named `<template>-<statefulset>-<ordinal>`: `data-kv-0` and
`data-kv-1`. They outlive the Pods, and the StatefulSet's deletion too.

## Question 5: never two versions at once (Chapter 16)

```bash
kubectl config use-context ckad2-b
kubectl patch deployment reports --type=json -p='[{"op":"replace","path":"/spec/strategy","value":{"type":"Recreate"}}]'
kubectl set image deployment/reports nginx=nginx:1.27
kubectl rollout status deployment/reports
```

`Recreate` stops all old Pods before it starts new ones. Replace the whole `strategy`:
a `rollingUpdate` block left behind next to `type: Recreate` is rejected.

## Question 6: switch from blue to green (Chapter 16)

```bash
kubectl patch service shop -p '{"spec":{"selector":{"app":"shop","version":"green"}}}'
kubectl get endpointslices -l kubernetes.io/service-name=shop
kubectl scale deployment shop-blue --replicas=0
```

Switch first, scale down after: green is already running, so the switch costs no
downtime, and blue stays available for a quick switch back until you scale it down.

## Question 7: roll back a Helm release (Chapter 14)

```bash
helm -n ckad2-deploy history catalog
helm -n ckad2-deploy get values catalog --revision 1
helm -n ckad2-deploy rollback catalog 1
kubectl -n ckad2-deploy rollout status deployment/catalog
```

A rollback is a new revision (3) with the manifests and values of revision 1; the
history keeps all three.

## Question 8: a Kustomize overlay with an image and a generator (Chapter 14)

`/tmp/kbook/ckad2/8/overlays/staging/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: ckad2-deploy
namePrefix: staging-
images:
  - name: nginx
    newTag: "1.27"
configMapGenerator:
  - name: app-config
    behavior: merge
    literals:
      - MODE=staging
```

```bash
kubectl kustomize /tmp/kbook/ckad2/8/overlays/staging | grep -E 'name:|image:|MODE'
kubectl apply -k /tmp/kbook/ckad2/8/overlays/staging
```

Kustomize names the generated ConfigMap `staging-app-config-<hash>` and rewrites the
Deployment's `configMapRef` to that name. A change of content changes the hash, which
rolls the Deployment. Without `behavior: merge`, a second generator with the same name
is an error.

## Question 9: a removed API version (Chapter 15)

```bash
kubectl api-resources | grep -i horizontal        # autoscaling/v2
sed -i 's|^apiVersion: autoscaling/v2beta2$|apiVersion: autoscaling/v2|' /tmp/kbook/ckad2/9/hpa.yaml
kubectl apply -f /tmp/kbook/ckad2/9/hpa.yaml
```

`autoscaling/v2beta2` was removed in Kubernetes 1.26; the fields of this manifest are
the same in `v2`.

## Question 10: a slow starter (Chapter 10)

Add to the container `slow` (with `kubectl -n ckad2-ops edit deployment slow`):

```yaml
          startupProbe:
            exec:
              command: ["cat", "/tmp/ready"]
            periodSeconds: 5
            failureThreshold: 12
```

The liveness and readiness probes wait until the startup probe has succeeded once.
5 seconds times 12 failures gives the container up to a minute to start.

## Question 11: who uses the CPU? (Chapter 15)

```bash
kubectl -n ckad2-ops top pod -l app=load --sort-by=cpu
kubectl -n ckad2-ops top pod -l app=load --sort-by=cpu --no-headers | awk 'NR==1 {print $1}' > /tmp/kbook/ckad2/11/pod.txt
```

## Question 12: a Pod that never starts (Chapter 07)

```bash
kubectl -n ckad2-ops get pod api-client                    # CreateContainerConfigError
kubectl -n ckad2-ops describe pod api-client | tail -3     # couldn't find key API_URL in ConfigMap
kubectl -n ckad2-ops patch configmap client-config -p '{"data":{"API_URL":"http://api"}}'
kubectl -n ckad2-ops get pod api-client -w
```

The kubelet retries on its own once the key exists; the Pod does not need to be
recreated.

## Question 13: a token for one audience (Chapter 23)

```bash
kubectl -n ckad2-sec create serviceaccount reporter
kubectl -n ckad2-sec patch serviceaccount reporter -p '{"automountServiceAccountToken":false}'
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: reporter
  namespace: ckad2-sec
spec:
  serviceAccountName: reporter
  volumes:
    - name: report-token
      projected:
        sources:
          - serviceAccountToken:
              audience: reports
              expirationSeconds: 3600
              path: token
  containers:
    - name: reporter
      image: busybox:1.36
      command: ["sleep", "infinity"]
      volumeMounts:
        - name: report-token
          mountPath: /var/run/reports
```

A token for the audience `reports` is accepted only by a service that checks for that
audience; the API server rejects it. The kubelet renews it before it expires.

## Question 14: read Pods and their logs (Chapter 23)

```bash
kubectl -n ckad2-sec create serviceaccount viewer
kubectl -n ckad2-sec create role pod-viewer --verb=get,list --resource=pods,pods/log
kubectl -n ckad2-sec create rolebinding viewer-binding --role=pod-viewer --serviceaccount=ckad2-sec:viewer
kubectl -n ckad2-sec auth can-i get pods --subresource=log --as=system:serviceaccount:ckad2-sec:viewer
```

Logs are the subresource `pods/log`; access to `pods` alone does not include them.

## Question 15: a TLS Secret from files (Chapter 07)

```bash
kubectl -n ckad2-sec create secret tls web-tls --cert=/tmp/kbook/ckad2/15/tls.crt --key=/tmp/kbook/ckad2/15/tls.key
kubectl -n ckad2-sec run web-tls --image=busybox:1.36 --dry-run=client -o yaml -- sleep infinity > web-tls.yaml
```

Add a `secret` volume for `web-tls` and a mount at `/etc/tls`, then apply. The Secret
has the type `kubernetes.io/tls` and the keys `tls.crt` and `tls.key`.

## Question 16: defaults for every container (Chapter 10)

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: defaults
  namespace: ckad2-quota
spec:
  limits:
    - type: Container
      default:
        cpu: 200m
        memory: 128Mi
      defaultRequest:
        cpu: 100m
        memory: 64Mi
```

```bash
kubectl -n ckad2-quota run plain --image=busybox:1.36 -- sleep infinity
kubectl -n ckad2-quota get pod plain -o jsonpath='{.spec.containers[0].resources}'
```

Create the LimitRange first: it applies when a Pod is admitted, never to Pods that
already exist.

## Question 17: one capability, a read-only root (Chapter 10)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: netadmin
  namespace: ckad2-sec
spec:
  volumes:
    - name: tmp
      emptyDir: {}
  containers:
    - name: netadmin
      image: busybox:1.36
      command: ["sleep", "infinity"]
      securityContext:
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
          add: ["NET_ADMIN"]
      volumeMounts:
        - name: tmp
          mountPath: /tmp
```

## Question 18: egress to one Service (Chapter 21)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-egress
  namespace: ckad2-net
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:
        - podSelector:
            matchLabels:
              app: backend
      ports:
        - protocol: TCP
          port: 80
```

Two traps: "by name" needs DNS, and the policy sees the connection after the Service
has translated it, so the port is the Pod's port, `80`, not the Service's `8080`.

## Question 19: a NodePort (Chapter 11)

```bash
kubectl -n ckad2-net expose deployment legacy --name=legacy-np --type=NodePort --port=80
kubectl -n ckad2-net patch service legacy-np --type=json -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":30180}]'
curl -s "http://$(kubectl get node kbook-worker -o jsonpath='{.status.addresses[0].address}'):30180" | head -4
```

## Question 20: an Ingress with TLS and a default backend (Chapter 12)

```bash
kubectl -n ckad2-net create ingress portal --class=nginx --default-backend=fallback:80 \
  --rule='portal.ckad2.example.test/api=api:80,tls=portal-tls'
kubectl -n ckad2-net get ingress portal -o yaml
```

A path without a trailing `*` gets the path type `Exact`; `tls=` in the rule adds the
host and Secret to `spec.tls`.
