# Mock exam CKA: solutions

Read these only after `make mock-score EXAM=cka`. Each entry shows one way to
answer the question; the checks accept any method that leaves the same result.
Every command runs on `cp1` unless it says `ssh`. The chapter in brackets teaches
the topic.

## Question 1: a user certificate (Chapter 23)

```bash
kubectl config use-context cka-a
cat > /tmp/kbook/cka/1/csr.yaml <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: jane
spec:
  request: $(base64 -w0 < /tmp/kbook/cka/1/jane.csr)
  signerName: kubernetes.io/kube-apiserver-client
  usages: [client auth]
EOF
kubectl apply -f /tmp/kbook/cka/1/csr.yaml
kubectl certificate approve jane
kubectl get csr jane -o jsonpath='{.status.certificate}' | base64 -d > /tmp/kbook/cka/1/jane.crt
kubectl -n cka-team create role pod-reader --verb=get,list,watch --resource=pods
kubectl -n cka-team create rolebinding jane-pods --role=pod-reader --user=jane
kubectl auth can-i list pods -n cka-team --as=jane     # yes
```

The certificate's common name (`CN=jane`) is the user name RBAC sees, and its
organization (`O=cka-devs`) would be a group. The `request` field holds the whole
PEM file, base64-encoded on one line.

## Question 2: install a component with Helm (Chapters 12 and 14)

```bash
cat > /tmp/kbook/cka/2/values.yaml <<'EOF'
replicaCount: 2
service:
  type: NodePort
EOF
helm install edge /tmp/kbook/cka/2/chart -n cka-infra --create-namespace -f /tmp/kbook/cka/2/values.yaml
helm -n cka-infra status edge
kubectl -n cka-infra get deployment,service
```

## Question 3: renew the API server certificate (Chapters 18 and 27)

```bash
sudo kubeadm certs check-expiration | grep apiserver
sudo kubeadm certs renew apiserver
sudo crictl ps --name kube-apiserver
sudo crictl --timeout 120s stop <CONTAINER-ID>   # the kubelet starts it again with the new certificate
kubectl get --raw /readyz                  # repeat until it answers ok
```

Renewing writes new files; a running API server keeps serving the old certificate
until it restarts. crictl gives up after two seconds by default, which is too short
for the API server to shut down; hence `--timeout`. Moving its manifest out of `/etc/kubernetes/manifests` and back
restarts it too. `kubeadm certs renew all` would also work, but renews more than the
question asks.

## Question 4: extension interfaces (Chapters 24 and 27)

```bash
ssh node1 sudo grep containerRuntimeEndpoint /var/lib/kubelet/config.yaml
ssh node1 sudo ls /etc/cni/net.d
```

Write the endpoint value (`unix:///var/run/containerd/containerd.sock`) on the first
line and the CNI file (`10-calico.conflist`) on the second. The kubelet talks to the
runtime through the CRI socket; the runtime sets up Pod networking with the first
CNI configuration file it finds in `/etc/cni/net.d`.

## Question 5: place a workload by node label and priority (Chapter 17)

```bash
kubectl create priorityclass cka-high --value=100000
kubectl label node node2 tier=compute
kubectl -n cka-work create deployment analytics --image=nginx:1.27 --replicas=2 --dry-run=client -o yaml > analytics.yaml
```

Add to the Pod template's `spec`, then `kubectl apply -f analytics.yaml`:

```yaml
      priorityClassName: cka-high
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: tier
                    operator: In
                    values: [compute]
```

## Question 6: autoscale a Deployment (Chapter 25)

```bash
kubectl -n cka-work autoscale deployment api --min=2 --max=6 --cpu=50%
kubectl -n cka-work patch hpa api --type=merge -p '{"spec":{"behavior":{"scaleDown":{"stabilizationWindowSeconds":60}}}}'
kubectl -n cka-work get hpa api
```

`kubectl autoscale` cannot set `behavior`; patch it or edit the HPA afterwards.

## Question 7: roll back to the first image (Chapter 05)

```bash
kubectl -n cka-work rollout history deployment/portal
kubectl -n cka-work rollout history deployment/portal --revision=1   # Image: nginx:1.25
kubectl -n cka-work rollout undo deployment/portal --to-revision=1
kubectl -n cka-work rollout status deployment/portal
```

`rollout undo` without `--to-revision` goes back one step only, to `nginx:1.26`.

## Question 8: route traffic with the Gateway API (Chapter 12)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-route
  namespace: cka-net
spec:
  parentRefs:
    - name: cka-gw
  hostnames: [api.cka.test]
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /v1
      backendRefs:
        - name: api
          port: 8080
          weight: 90
        - name: api-v2
          port: 8080
          weight: 10
```

Weights are relative within one rule: 90 and 10 send 90% and 10% of the matching
requests.

## Question 9: ingress from a partner Namespace (Chapter 21)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-ingress
  namespace: cka-net
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              purpose: partners
          podSelector:
            matchLabels:
              role: client
      ports:
        - protocol: TCP
          port: 80
```

`namespaceSelector` and `podSelector` in **one** `from` entry mean both must match.
As two entries (each with its own `-`), either would be enough, and the Pod `local`
in `cka-net` (labeled `role=client`) would get in.

## Question 10: a NodePort Service (Chapter 11)

```bash
kubectl -n cka-net expose deployment legacy --name=legacy-np --type=NodePort --port=80
kubectl -n cka-net patch service legacy-np --type=json -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":30080}]'
curl -s http://192.168.56.10:30080 | head -4
```

## Question 11: a name in CoreDNS (Chapter 21)

```bash
kubectl -n kube-system edit configmap coredns
```

Add one line inside the `.:53 { ... }` block, before the `kubernetes` line:

```text
    rewrite name exact shop.cka.local legacy.cka-net.svc.cluster.local
```

```bash
kubectl -n cka-net exec local -- nslookup shop.cka.local.     # after up to a minute
```

CoreDNS's `reload` plugin reads the changed ConfigMap on its own, after the kubelet
has updated the mounted file. A `hosts` entry with the Service's IP would work too,
but it breaks when the Service is recreated.

## Question 12: a local volume, bound when used (Chapters 13 and 22)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-wait
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: fast-pv
spec:
  capacity:
    storage: 1Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-wait
  local:
    path: /srv/cka-fast
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values: [node2]
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fast
  namespace: cka-data
spec:
  storageClassName: local-wait
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 500Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: fast-writer
  namespace: cka-data
spec:
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: fast
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh", "-c", "echo ok > /data/ok; sleep infinity"]
      volumeMounts:
        - name: data
          mountPath: /data
```

The claim stays `Pending` until the Pod exists: `WaitForFirstConsumer` binds it only
once the scheduler has chosen a node. A `local` volume needs `nodeAffinity`, which
also steers the Pod to `node2`.

## Question 13: keep the data (Chapter 13)

```bash
kubectl patch pv archive-pv -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: archive
  namespace: cka-data
spec:
  storageClassName: manual
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
```

## Question 14: node1 is NotReady (Chapter 27)

```bash
kubectl describe node node1 | grep -A3 Conditions      # container runtime is down
ssh node1
sudo systemctl status containerd                       # inactive (dead), disabled
sudo systemctl enable --now containerd
exit
kubectl get nodes
```

`enable --now` starts it and makes it start at boot; `start` alone would leave the
node broken after the next reboot.

## Question 15: a second scheduler that does not run (Chapter 27)

```bash
kubectl -n cka-ops get pods                                  # cka-scheduler-cp1 CrashLoopBackOff
kubectl -n cka-ops logs cka-scheduler-cp1                    # ... /etc/kubernetes/schedular.conf: no such file
sudo cat /etc/kubernetes/manifests/cka-scheduler.yaml        # --config=/etc/kubernetes/cka-scheduler-config.yaml
sudo sed -i 's|schedular.conf|scheduler.conf|' /etc/kubernetes/cka-scheduler-config.yaml
sudo mv /etc/kubernetes/manifests/cka-scheduler.yaml /tmp/ && sleep 20 && sudo mv /tmp/cka-scheduler.yaml /etc/kubernetes/manifests/
kubectl -n cka-ops get pods -w
```

The manifest was right; the configuration file it points at named a kubeconfig that
does not exist. Fixing the file is enough, but the kubelet retries a crashing
container with a growing delay (up to five minutes); moving the manifest out and
back starts it at once.

## Question 16: who uses the memory? (Chapter 25)

```bash
kubectl -n cka-ops top pod -l app=meter --sort-by=memory
kubectl -n cka-ops top pod -l app=meter --sort-by=memory --no-headers | awk 'NR==1 {print $1}' > /tmp/kbook/cka/16/pod.txt
```

## Question 17: out of a locked-down Namespace (Chapter 21)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: client-egress
  namespace: cka-ops
spec:
  podSelector:
    matchLabels:
      app: client
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
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: cka-net
          podSelector:
            matchLabels:
              app: web
      ports:
        - protocol: TCP
          port: 80
```

Policies add up: `lockdown` still denies everything else, and this one allows two
destinations. Without the DNS rule, `wget http://web.cka-net` fails before it
connects, because the name never resolves. The egress port is the Pod's port (80),
not a Service port.

## Question 18: a Pod that no node accepts (Chapter 17)

```bash
kubectl -n cka-ops describe pod -l app=infra-agent | tail -3   # didn't match Pod's node affinity/selector
kubectl -n cka-ops get deployment infra-agent -o jsonpath='{.spec.template.spec.nodeSelector}'
kubectl label node node2 role=infra
kubectl -n cka-ops get pods -o wide
```
