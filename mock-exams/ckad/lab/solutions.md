# Mock exam CKAD: solutions

Read these only after `make mock-score EXAM=ckad`. Each entry shows one way to
answer the question; the checks accept any method that leaves the same result.
The chapter in brackets teaches the topic.

## Question 1: rebuild an image (Chapter 16)

```bash
cd /tmp/kbook/ckad/1/app
sed -i 's/^ENV APP_VERSION=.*/ENV APP_VERSION=2.0/' Dockerfile
docker build -t ckad-web:2.0 .
docker save -o /tmp/kbook/ckad/1/ckad-web.tar ckad-web:2.0
```

With Podman: `podman build -t ckad-web:2.0 .` and
`podman save --format docker-archive -o /tmp/kbook/ckad/1/ckad-web.tar ckad-web:2.0`.
An `ENV` line is part of the image's configuration, so changing it needs a new
build; setting the variable in a Pod would not change the image.

## Question 2: a sidecar that ships a log (Chapter 09)

Add to the Pod's `spec` in `logger.yaml`, then `kubectl apply -f logger.yaml`:

```yaml
  initContainers:
    - name: shipper
      image: busybox:1.36
      restartPolicy: Always
      command: ["sh", "-c", "tail -F /var/log/app/app.log"]
      volumeMounts:
        - name: logs
          mountPath: /var/log/app
```

```bash
kubectl -n ckad-design logs logger -c shipper --tail=3
```

A native sidecar is an init container with `restartPolicy: Always`: it starts
before the app and keeps running beside it. `tail -F` waits for the file to appear.

## Question 3: an agent on every node (Chapters 09 and 17)

```bash
kubectl -n ckad-design create deployment node-agent --image=busybox:1.36 --dry-run=client -o yaml -- sleep 3600 > ds.yaml
```

Change `kind` to `DaemonSet`, delete `replicas`, `strategy`, and `status`, and add
to the Pod template's `spec`:

```yaml
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
```

```bash
kubectl apply -f ds.yaml
kubectl -n ckad-design get daemonset node-agent     # DESIRED and READY equal the node count
```

Without the toleration, the DaemonSet skips the control plane node because of its taint.
If `DESIRED` is still lower than the node count, another taint is in the way (for
example one left from Chapter 17's lab): `kubectl describe nodes | grep Taints`
shows it. A toleration with only `operator: Exists`, and no key, tolerates every taint.

## Question 4: scratch space in memory (Chapter 13)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: scratch
  namespace: ckad-design
spec:
  volumes:
    - name: scratch
      emptyDir:
        medium: Memory
        sizeLimit: 64Mi
  containers:
    - name: scratch
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: scratch
          mountPath: /scratch
```

`medium: Memory` puts the `emptyDir` on a tmpfs; what it holds counts against the
container's memory.

## Question 5: a careful rolling update (Chapters 05 and 16)

```bash
kubectl config use-context ckad-b
kubectl patch deployment frontend -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
kubectl set image deployment/frontend nginx=nginx:1.27
kubectl rollout status deployment/frontend
```

With `maxUnavailable: 0`, a new Pod must be ready before an old one goes, so
capacity never drops. Set the strategy first: the rollout starts as soon as the
image changes.

## Question 6: a canary (Chapter 16)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-canary
  namespace: ckad-deploy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: checkout
      track: canary
  template:
    metadata:
      labels:
        app: checkout
        track: canary
    spec:
      containers:
        - name: checkout
          image: nginx:1.27
```

```bash
kubectl get endpointslices -l kubernetes.io/service-name=checkout
```

The Service selects only `app=checkout`, so it balances over all five Pods: one
in five requests reaches the canary. The two Deployments' selectors differ by
`track`, so neither adopts the other's Pods.

## Question 7: upgrade a Helm release (Chapter 14)

```bash
helm -n ckad-deploy get values cache                 # shows greeting: hello-ckad
helm -n ckad-deploy upgrade cache /tmp/kbook/ckad/7/chart \
  --reuse-values --set image.tag=1.27 --set replicaCount=3
helm -n ckad-deploy get values cache
```

Without `--reuse-values` (or `--set greeting=hello-ckad` again), an upgrade starts
from the chart's defaults, and the greeting falls back to `hello-default`.

## Question 8: a Kustomize overlay (Chapter 14)

`/tmp/kbook/ckad/8/overlays/prod/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: ckad-deploy
replicas:
  - name: ledger
    count: 2
labels:
  - pairs:
      env: prod
    includeTemplates: true
```

```bash
kubectl kustomize /tmp/kbook/ckad/8/overlays/prod     # check the output first
kubectl apply -k /tmp/kbook/ckad/8/overlays/prod
```

`labels` with `includeTemplates` labels the Pod template too, but leaves the
selector alone. `commonLabels` works as well; it also changes the selector.

## Question 9: a removed API version (Chapters 02 and 15)

```bash
kubectl api-resources | grep -i cronjob     # cronjobs ... batch/v1
sed -i 's|^apiVersion: batch/v1beta1$|apiVersion: batch/v1|' /tmp/kbook/ckad/9/cleanup.yaml
kubectl apply -f /tmp/kbook/ckad/9/cleanup.yaml
```

`batch/v1beta1` CronJobs were removed in Kubernetes 1.25. The fields did not
change, so the API version is the only edit.

## Question 10: probes (Chapter 10)

```bash
kubectl -n ckad-ops edit deployment api
```

Add to the container `nginx`:

```yaml
          readinessProbe:
            httpGet:
              path: /
              port: 80
            periodSeconds: 5
          livenessProbe:
            tcpSocket:
              port: 80
            initialDelaySeconds: 10
            periodSeconds: 20
```

```bash
kubectl -n ckad-ops rollout status deployment/api
```

## Question 11: errors from one container (Chapter 15)

```bash
kubectl -n ckad-ops logs batch-runner -c worker | grep ERROR > /tmp/kbook/ckad/11/errors.txt
```

Without `-c`, kubectl asks which container you mean. The `fetch` container also
prints an `ERROR` line, which does not belong in the file.

## Question 12: a Deployment that keeps crashing (Chapters 07 and 15)

```bash
kubectl -n ckad-ops get pods -l app=reports              # CrashLoopBackOff
kubectl -n ckad-ops logs deploy/reports                  # missing /config/settings.conf
kubectl -n ckad-ops get configmap reports-config -o yaml # the key is settings.cfg
kubectl -n ckad-ops edit configmap reports-config        # rename the key to settings.conf
kubectl -n ckad-ops rollout restart deployment/reports
kubectl -n ckad-ops rollout status deployment/reports
```

Each ConfigMap key becomes a file of that name in the mounted directory. Renaming
the key fixes it; so does `items` in the volume, which maps `settings.cfg` to the
path `settings.conf`. The restart gives new Pods at once, instead of waiting for
the kubelet to refresh the volume and for the next crash-loop retry.

## Question 13: configuration and credentials as files (Chapter 07)

```bash
kubectl -n ckad-sec create configmap db-config --from-file=/tmp/kbook/ckad/13/db.properties
kubectl -n ckad-sec create secret generic db-cred --from-literal=username=app --from-literal=password=s3cr3t
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: db-client
  namespace: ckad-sec
spec:
  volumes:
    - name: config
      configMap:
        name: db-config
    - name: cred
      secret:
        secretName: db-cred
  containers:
    - name: db-client
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: config
          mountPath: /etc/db-config
        - name: cred
          mountPath: /etc/db-cred
          readOnly: true
```

`--from-file` uses the file name as the key; `/etc/db-config/db.properties` is the
file inside the Pod.

## Question 14: a hardened Pod (Chapter 10)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hardened
  namespace: ckad-sec
spec:
  securityContext:
    runAsUser: 1000
    runAsGroup: 3000
    runAsNonRoot: true
  containers:
    - name: hardened
      image: busybox:1.36
      command: ["sleep", "3600"]
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
```

```bash
kubectl -n ckad-sec exec hardened -- id      # uid=1000 gid=3000
```

`capabilities`, `allowPrivilegeEscalation`, and `readOnlyRootFilesystem` exist only
in the container's `securityContext`; the user and group can go in either.

## Question 15: permissions for a ServiceAccount (Chapter 23)

```bash
kubectl -n ckad-sec create serviceaccount deployer
kubectl -n ckad-sec create role deploy-editor --verb=get,list,create,update,patch --resource=deployments.apps
kubectl -n ckad-sec create rolebinding deployer-binding --role=deploy-editor --serviceaccount=ckad-sec:deployer
kubectl -n ckad-sec create deployment ci --image=nginx:1.27
kubectl -n ckad-sec set serviceaccount deployment ci deployer
kubectl -n ckad-sec auth can-i create deployments --as=system:serviceaccount:ckad-sec:deployer   # yes
kubectl -n ckad-sec auth can-i delete deployments --as=system:serviceaccount:ckad-sec:deployer   # no
```

## Question 16: requests and limits under a quota (Chapter 10)

```bash
kubectl -n ckad-quota get events --field-selector reason=FailedCreate | tail -2
kubectl -n ckad-quota set resources deployment burst --requests=cpu=100m,memory=64Mi --limits=cpu=200m,memory=128Mi
kubectl -n ckad-quota rollout status deployment/burst
```

The events say `must specify limits.cpu, limits.memory, requests.cpu, requests.memory`:
a quota on those resources rejects every Pod that does not state them. Three Pods
use 300m of the quota's 1 CPU of requests, so they fit.

## Question 17: a custom resource (Chapter 24)

```bash
kubectl api-resources | grep -i cache       # caches  cch  ckad.kbook.io/v1  true  Cache
kubectl explain cache.spec
```

```yaml
apiVersion: ckad.kbook.io/v1
kind: Cache
metadata:
  name: session-cache
  namespace: ckad-sec
spec:
  size: medium
  replicas: 3
```

The schema allows `small`, `medium`, and `large`; another size is rejected.

## Question 18: a Service that reaches nothing (Chapters 11 and 26)

```bash
kubectl -n ckad-net get endpointslices -l kubernetes.io/service-name=catalog   # no endpoints
kubectl -n ckad-net get service catalog -o yaml | grep -A3 ports               # targetPort: web
kubectl -n ckad-net get deployment catalog -o yaml | grep -A3 ports            # name: http
kubectl -n ckad-net patch service catalog --type=json -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":"http"}]'
kubectl -n ckad-net exec probe -- wget -qO- -T 3 http://catalog | head -4
```

A named `targetPort` must match a port name in the Pods. `targetPort: 80` works as well.

## Question 19: protect the database (Chapter 21)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-access
  namespace: ckad-net
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api
      ports:
        - protocol: TCP
          port: 80
```

```bash
kubectl -n ckad-net exec api -- wget -qO- -T 2 http://db | head -1    # works
kubectl -n ckad-net exec web -- wget -qO- -T 2 http://db              # times out
```

Selecting `db` for ingress denies everything the policy does not allow. Other Pods
are not selected, so their traffic is unchanged.

## Question 20: a Service and an Ingress (Chapter 12)

```bash
kubectl -n ckad-net expose deployment cart --port=8080 --target-port=80
kubectl -n ckad-net create ingress store --class=nginx \
  --rule='store.ckad.example.test/shop*=shop:80' \
  --rule='store.ckad.example.test/cart*=cart:8080'
kubectl -n ckad-net get ingress store -o yaml
```

A trailing `*` in the path makes `kubectl create ingress` use the path type
`Prefix`; without it, the type is `Exact`.
