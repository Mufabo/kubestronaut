# Mock exam Part III: solutions

Read these only after `make mock-score EXAM=part3`. Each entry shows one way to
answer the question. The checks accept any method that leaves the same result.
Every command runs on `cp1` unless it says `ssh`.

## Question 1: `fast` on the control plane node

```bash
kubectl config use-context p3-a
kubectl -n p3-sched run fast --image=nginx:1.27 --dry-run=client -o yaml > fast.yaml
```

Add to the Pod's `spec`:

```yaml
  nodeSelector:
    kubernetes.io/hostname: cp1
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
```

```bash
kubectl -n p3-sched apply -f fast.yaml
kubectl -n p3-sched get pod fast -o wide
```

The selector says where the Pod must go; the toleration only lets it go there.
`nodeName` would skip the scheduler and its checks altogether (Chapter 17).
While `cp1` is cordoned for Question 4, the Pod waits in `Pending`.

## Question 2: the static Pod `ops-monitor`

```bash
kubectl -n p3-ops run ops-monitor --image=busybox:1.36 --dry-run=client -o yaml --command -- sleep infinity > ops-monitor.yaml
# add "namespace: p3-ops" under metadata, then:
sudo cp ops-monitor.yaml /etc/kubernetes/manifests/
kubectl -n p3-ops get pod ops-monitor-cp1
```

The kubelet runs every manifest in `/etc/kubernetes/manifests` and shows a mirror
Pod named after the Pod and the node. The namespace comes from the manifest's
`metadata`, not from your context.

## Question 3: the join command

```bash
sudo kubeadm token create --print-join-command | tee /tmp/kbook/part3/3/join.sh
```

A fresh token, valid for 24 hours, and the CA hash, in one line (Chapter 18).

## Question 4: upgrade the control plane

As in Chapter 19, on `cp1`:

```bash
sudo sed -i "s|/v1.36/|/v1.37/|" /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.37.0-1.1
sudo apt-mark hold kubeadm
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply -y v1.37.0

kubectl drain cp1 --ignore-daemonsets
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.37.0-1.1 kubectl=1.37.0-1.1
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
kubectl get nodes          # repeat until it answers and cp1 shows v1.37.0
kubectl uncordon cp1
```

If `upgrade apply` stops in its preflight with `[ERROR CreateJob]: Job
"upgrade-health-check-..." ... did not complete in 15s`, the cluster was too busy
to run its health-check Job in time. Nothing has changed yet; run the same
command again.

After the kubelet restart, the API server goes away for a minute while its
static Pod restarts. Repeat any command that fails with `connection refused`
before you move on.

## Question 5: `report`

```bash
kubectl config use-context p3-b
kubectl describe pod -l app=report | grep -A2 -i "image"
kubectl set image deployment/report report=nginx:1.27
kubectl rollout status deployment/report
```

The tag was `1.27-reprot`. The events show `ErrImagePull` and `ImagePullBackOff`.

## Question 6: back up etcd

```bash
sudo etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /tmp/kbook/part3/6/etcd.db
sudo etcdutl snapshot status /tmp/kbook/part3/6/etcd.db -w table
```

The certificate paths are in `/etc/kubernetes/manifests/etcd.yaml` (Chapter 20).

## Question 7: `db-allow`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-allow
  namespace: p3-net
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
kubectl apply -f db-allow.yaml
kubectl -n p3-net exec api -- wget -q -T 3 -O - http://db | head -4
kubectl -n p3-net exec other -- wget -q -T 3 -O - http://db      # times out
```

Selecting `db` makes it deny all ingress except what the rule allows (Chapter 21).

## Question 8: the Service network

```bash
sudo grep service-cluster-ip-range /etc/kubernetes/manifests/kube-apiserver.yaml
echo 10.96.0.0/12 > /tmp/kbook/part3/8/service-cidr.txt
```

kubeadm's default, set on the API server. The `kubeadm-config` ConfigMap shows it
too, as `serviceSubnet`.

## Question 9: `logs-pv`, `logs`, and `writer`

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: logs-pv
spec:
  capacity:
    storage: 1Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /srv/p3-logs
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: logs
  namespace: p3-data
spec:
  storageClassName: manual
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 500Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: writer
  namespace: p3-data
spec:
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sleep", "infinity"]
      volumeMounts:
        - name: logs
          mountPath: /logs
  volumes:
    - name: logs
      persistentVolumeClaim:
        claimName: logs
```

A claim binds to a PV with the same storage class whose capacity and access mode
fit; 500Mi fits into 1Gi (Chapters 13 and 22).

## Question 10: `deployer`

```bash
kubectl config use-context p3-b
kubectl create serviceaccount deployer
kubectl create role deploy-manager --verb=get,list,create,update --resource=deployments.apps
kubectl create rolebinding deployer --role=deploy-manager --serviceaccount=p3-apps:deployer
kubectl auth can-i create deployments --as=system:serviceaccount:p3-apps:deployer
kubectl auth can-i delete deployments --as=system:serviceaccount:p3-apps:deployer
```

The answers are `yes` and `no` (Chapter 23).

## Question 11: `auditor`

```bash
kubectl config use-context p3-a
kubectl create clusterrole node-reader --verb=get,list --resource=nodes
kubectl create clusterrolebinding auditor-nodes --clusterrole=node-reader --user=auditor
kubectl auth can-i list nodes --as=auditor
```

Nodes are cluster-scoped, so only a ClusterRole with a ClusterRoleBinding can grant them.

## Question 12: the Backup `nightly`

```bash
kubectl get crd | grep kbook
kubectl explain backup.spec
```

```yaml
apiVersion: ops.kbook.io/v1
kind: Backup
metadata:
  name: nightly
  namespace: p3-ops
spec:
  schedule: "0 2 * * *"
  retain: 7
```

Quote the schedule: unquoted, `*` starts a YAML alias (Chapter 24).

## Question 13: the HPA `web`

```bash
kubectl config use-context p3-b
kubectl autoscale deployment web --min=2 --max=5 --cpu=60%
```

The HPA reports `<unknown>` for its metric, because this cluster has no
metrics-server; the object itself is what the question asks for (Chapter 25).

## Question 14: `shop`

```bash
kubectl config use-context p3-b
kubectl get endpointslices -l kubernetes.io/service-name=shop
kubectl get service shop -o yaml | grep -A3 ports
kubectl patch service shop --type=json -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":80}]'
kubectl exec probe -- wget -q -T 3 -O - http://shop | head -4
```

The Service had endpoints, so the selector was right; the port was not:
`targetPort: 8080`, while nginx listens on 80 (Chapter 26).

## Question 15: node2

```bash
ssh node2
sudo systemctl status kubelet          # failed: status=203/EXEC
sudo systemctl cat kubelet | grep ExecStart
ls /usr/local/bin/kubelet /usr/bin/kubelet
sudo vim /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf   # ExecStart=/usr/bin/kubelet ...
sudo systemctl daemon-reload
sudo systemctl enable --now kubelet
sudo systemctl restart kubelet
exit
kubectl get nodes
```

Exit status 203 means systemd could not execute the program: the drop-in named
`/usr/local/bin/kubelet`, which does not exist. Forgetting `daemon-reload` keeps
the old unit in effect (Chapter 27).

## Question 16: the etcd CA

```bash
sudo openssl x509 -enddate -noout -in /etc/kubernetes/pki/etcd/ca.crt
sudo openssl x509 -enddate -noout -in /etc/kubernetes/pki/etcd/ca.crt | cut -d= -f2 > /tmp/kbook/part3/16/etcd-ca-expiry.txt
```

etcd has its own CA, `etcd/ca.crt`, separate from the cluster CA `ca.crt`.
`kubeadm certs check-expiration` lists it as `etcd-ca`.
