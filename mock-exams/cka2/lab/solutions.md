# Mock exam CKA, set 2: solutions

Read these only after `make mock-score EXAM=cka2`. Each entry shows one way to
answer the question; the checks accept any method that leaves the same result.
Every command runs on `cp1` unless it says `ssh`. The chapter in brackets teaches
the topic.

## Question 1: a user, a certificate, and a kubeconfig (Chapters 03, 23, and 30)

```bash
cd /tmp/kbook/cka2/1
openssl genrsa -out dev.key 2048
openssl req -new -key dev.key -subj "/CN=dev" -out dev.csr
sudo openssl x509 -req -in dev.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key \
  -CAcreateserial -CAserial /tmp/ca.srl -days 30 -out dev.crt
sudo chown "$(id -u)" dev.crt
kubectl config --kubeconfig=dev.kubeconfig set-cluster kbook-vm --server=https://192.168.56.10:6443 \
  --certificate-authority=/etc/kubernetes/pki/ca.crt --embed-certs=true
kubectl config --kubeconfig=dev.kubeconfig set-credentials dev --client-certificate=dev.crt --client-key=dev.key --embed-certs=true
kubectl config --kubeconfig=dev.kubeconfig set-context dev --cluster=kbook-vm --user=dev --namespace=cka2-dev
kubectl config --kubeconfig=dev.kubeconfig use-context dev
kubectl -n cka2-dev create rolebinding dev-edit --clusterrole=edit --user=dev
kubectl --kubeconfig=dev.kubeconfig auth whoami
```

Signing with the CA key directly works only where the key is, on the control plane
node; a CertificateSigningRequest (set 1, Question 1) works from anywhere. Either way,
Kubernetes cannot revoke the certificate, so keep its lifetime short.

## Question 2: reports for everyone who may view (Chapter 23)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cka2-reports-viewer
  labels:
    rbac.authorization.k8s.io/aggregate-to-view: "true"
rules:
  - apiGroups: [cka2.kbook.io]
    resources: [reports]
    verbs: [get, list, watch]
```

```bash
kubectl auth can-i list reports.cka2.kbook.io -n cka2-team --as=amy --as-group=analysts
```

The `view`, `edit`, and `admin` ClusterRoles have an aggregation rule: a controller
copies the rules of every ClusterRole with the matching label into them. That is how
operators make their custom resources readable by existing roles.

## Question 3: install a component with Kustomize (Chapter 14)

`/tmp/kbook/cka2/3/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - components.yaml
patches:
  - target:
      kind: Deployment
      name: metrics-server
      namespace: kube-system
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/args/-
        value: --kubelet-insecure-tls
```

```bash
kubectl kustomize /tmp/kbook/cka2/3 | grep -- --kubelet-insecure-tls
kubectl apply -k /tmp/kbook/cka2/3
kubectl -n kube-system rollout status deployment/metrics-server
kubectl top nodes
```

The path ending in `/-` appends to the list. kubeadm's kubelets serve self-signed
certificates, which metrics-server cannot verify without this argument.

## Question 4: a failed release (Chapter 14)

```bash
helm list -A --failed
helm -n cka2-legacy uninstall jobs
helm list -A
```

## Question 5: never two on one node (Chapter 17)

Add to the Pod template's `spec` of a generated Deployment:

```yaml
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - topologyKey: kubernetes.io/hostname
              labelSelector:
                matchLabels:
                  app: cache
```

With node2 broken (Question 14), only `cp1` and `node1` are left; the toleration makes
`cp1` a candidate, so both replicas still find a node.

## Question 6: Pods that never fit (Chapter 10)

```bash
kubectl config use-context cka2-b
kubectl describe pod -l app=big | grep -A2 Events      # 0/3 nodes are available: Insufficient cpu
kubectl set resources deployment big --requests=cpu=100m,memory=64Mi
kubectl rollout status deployment/big
```

Each VM has one CPU; a request of 2 CPUs fits nowhere, however idle the nodes are.

## Question 7: a static Pod on node1 (Chapter 17)

```bash
ssh node1
sudo vim /etc/kubernetes/manifests/node-probe.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: node-probe
  namespace: cka2-work
spec:
  containers:
    - name: probe
      image: busybox:1.36
      command: ["sleep", "infinity"]
```

```bash
exit
kubectl -n cka2-work get pod node-probe-node1
```

## Question 8: route by header (Chapter 12)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: version-route
  namespace: cka2-net
spec:
  parentRefs:
    - name: cka2-gw
  hostnames: [app.cka2.test]
  rules:
    - matches:
        - headers:
            - name: X-Version
              value: v2
      backendRefs:
        - name: app-v2
          port: 80
    - backendRefs:
        - name: app-v1
          port: 80
```

A rule without `matches` matches every path (`PathPrefix /`). The more specific
header match wins over it.

## Question 9: a Pod with its own DNS settings (Chapter 21)

```bash
kubectl -n kube-system get service kube-dns -o jsonpath='{.spec.clusterIP}'
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dns-client
  namespace: cka2-net
spec:
  dnsPolicy: None
  dnsConfig:
    nameservers: [10.96.0.10]
    searches: [cka2-net.svc.cluster.local]
    options:
      - name: ndots
        value: "2"
  containers:
    - name: client
      image: busybox:1.36
      command: ["sleep", "infinity"]
```

With `dnsPolicy: None`, only `dnsConfig` fills `/etc/resolv.conf`. With the default
`ClusterFirst`, `dnsConfig` is merged into the cluster's settings instead.

## Question 10: a Service for something outside the cluster (Chapter 11)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: legacy-db
  namespace: cka2-net
spec:
  ports:
    - port: 5432
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: legacy-db-1
  namespace: cka2-net
  labels:
    kubernetes.io/service-name: legacy-db
addressType: IPv4
ports:
  - port: 5432
    protocol: TCP
endpoints:
  - addresses: [10.0.0.50]
```

Without a selector, the EndpointSlice controller leaves the Service alone; the label
`kubernetes.io/service-name` ties a hand-made slice to it. Its port must have the same
name as the Service's port (here, none).

## Question 11: lock a Namespace down (Chapter 36)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: cka2-locked
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: cka2-locked
spec:
  podSelector: {}
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
```

## Question 12: a claim for the right volume (Chapter 13)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: reports
  namespace: cka2-data
spec:
  storageClassName: manual
  accessModes: [ReadWriteOnce]
  selector:
    matchLabels:
      tier: reports
  resources:
    requests:
      storage: 1Gi
```

Without the selector, the claim binds to the smallest volume that fits, which is the
`tier=archive` one.

## Question 13: part of a volume, read-only (Chapter 13)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: reader
  namespace: cka2-data
spec:
  volumes:
    - name: shared
      persistentVolumeClaim:
        claimName: shared
  containers:
    - name: reader
      image: busybox:1.36
      command: ["sleep", "infinity"]
      volumeMounts:
        - name: shared
          mountPath: /data
          subPath: logs
          readOnly: true
```

## Question 14: node2 is NotReady (Chapter 27)

```bash
ssh node2
sudo systemctl status kubelet                 # not running; it keeps restarting
sudo journalctl -u kubelet -n 20 | grep failed # failed to run Kubelet: open /etc/kubernetes/pki/ca-cert.crt: no such file or directory
sudo sed -i 's|/etc/kubernetes/pki/ca-cert.crt|/etc/kubernetes/pki/ca.crt|' /var/lib/kubelet/config.yaml
sudo systemctl restart kubelet
exit
kubectl get nodes
```

## Question 15: a kubeconfig that does not trust the server (Chapter 30)

```bash
kubectl --kubeconfig /tmp/kbook/cka2/15/ops.kubeconfig get pods    # x509: certificate signed by unknown authority
kubectl config --kubeconfig /tmp/kbook/cka2/15/ops.kubeconfig set-cluster kbook-vm \
  --certificate-authority=/etc/kubernetes/pki/ca.crt --embed-certs=true
kubectl --kubeconfig /tmp/kbook/cka2/15/ops.kubeconfig get pods
```

The client checks the API server's certificate against the CA in the kubeconfig; the
file named another CA. `--insecure-skip-tls-verify` would also make it work, but
without any protection against a server that is not the cluster's.

## Question 16: what the previous container said (Chapter 15)

```bash
kubectl -n cka2-ops get pod cruncher                       # RESTARTS 1
kubectl -n cka2-ops logs cruncher --previous > /tmp/kbook/cka2/16/line.txt
```

## Question 17: a policy that blocks its own client (Chapter 21)

```bash
kubectl -n cka2-net get networkpolicy restrict -o yaml | grep -A3 podSelector   # role: cilent
kubectl -n cka2-net get pod client --show-labels                                # role=client
kubectl -n cka2-net edit networkpolicy restrict                                 # cilent -> client
kubectl -n cka2-net exec client -- wget -qO- -T 3 http://api | head -2
```

## Question 18: the etcd member (Chapter 20)

```bash
sudo etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key member list -w table
echo "cp1 https://192.168.56.10:2380" > /tmp/kbook/cka2/18/etcd.txt
```

The peer URL (port 2380) is what other members use to reach this one; the client URL
(port 2379) is what the API server uses.
