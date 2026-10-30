# Chapter 33 lab: solutions

Every command runs on `cp1`. Each task has other valid answers; the checks look at
the result, not at the commands.

## Task 1: Find the Pods that break baseline

```bash
kubectl label --dry-run=server --overwrite namespace ch33-legacy pod-security.kubernetes.io/enforce=baseline
```

```text
Warning: existing pods in namespace "ch33-legacy" violate the new PodSecurity enforce level "baseline:latest"
Warning: backup: hostPath volumes
Warning: debugger: privileged
Warning: metrics: host namespaces
namespace/ch33-legacy labeled (server dry run)
```

```bash
printf 'backup\ndebugger\nmetrics\n' > /tmp/ch33-violations.txt
kubectl label --overwrite namespace ch33-legacy pod-security.kubernetes.io/enforce=baseline pod-security.kubernetes.io/warn=restricted
```

`cache` runs as root, and `web` sets nothing: `baseline` allows both, `restricted`
would not. The real label prints the same warnings, plus those for `restricted`;
the running Pods are not touched.

## Task 2: Run a Deployment under restricted

```bash
kubectl -n ch33-apps get events --field-selector reason=FailedCreate | tail -1
kubectl -n ch33-apps edit deployment worker
```

Add to the Pod template's `spec`:

```yaml
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
```

and to the container `busybox`:

```yaml
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
```

```bash
kubectl -n ch33-apps rollout status deployment/worker
```

The ReplicaSet controller retries on its own; once the template passes, the Pods
appear.

## Task 3: Consume a Secret safely

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: ch33-apps
spec:
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  volumes:
    - name: db
      secret:
        secretName: db-pass
        defaultMode: 0400
  containers:
    - name: api
      image: busybox:1.36
      command: ["sleep", "infinity"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
      volumeMounts:
        - name: db
          mountPath: /etc/db
          readOnly: true
```

```bash
kubectl -n ch33-apps exec api -- stat -L -c %a /etc/db/password       # 400
kubectl -n ch33-apps exec api -- ls /var/run/secrets/kubernetes.io      # No such file or directory
```

`defaultMode: 0400` is octal in YAML; in JSON, write the decimal `256`. The files
in a Secret volume are symlinks, so `stat -L` follows them. Mode `0400` makes the
file readable only by its owner, root; to let user 1000 read it, add `fsGroup` and
use mode `0440`. The task asks only for the mode.

## Task 4: Encrypt Secrets at rest

```bash
sudo mkdir -p /etc/kubernetes/enc
head -c 32 /dev/urandom | base64          # the key
sudo vim /etc/kubernetes/enc/enc.yaml
sudo chmod 600 /etc/kubernetes/enc/enc.yaml
```

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <the key>
      - identity: {}
```

Then edit the API server's manifest (keep a copy outside the manifests directory
first):

```bash
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak
sudo vim /etc/kubernetes/manifests/kube-apiserver.yaml
```

Add the flag to `command`, a mount to the container, and a volume:

```yaml
    - --encryption-provider-config=/etc/kubernetes/enc/enc.yaml
```

```yaml
    - mountPath: /etc/kubernetes/enc
      name: enc
      readOnly: true
```

```yaml
  - hostPath:
      path: /etc/kubernetes/enc
      type: DirectoryOrCreate
    name: enc
```

Wait until the API server is back (`sudo crictl ps --name kube-apiserver`, then
`kubectl get --raw /readyz`), rewrite the Secrets, and check etcd:

```bash
kubectl -n ch33-apps get secrets -o json | kubectl replace -f -
sudo etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
  get /registry/secrets/ch33-apps/db-pass | hexdump -C | head -3
```

The value starts with `k8s:enc:aescbc:v1:key1:`. If the API server does not come
back, `sudo crictl ps -a --name kube-apiserver` and `sudo crictl logs` on the newest
container show why; a missing mount gives "no such file or directory" for the
configuration file.

## Task 5: Run a Pod in a sandbox

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
---
apiVersion: v1
kind: Pod
metadata:
  name: sandboxed
  namespace: ch33-sandbox
spec:
  runtimeClassName: gvisor
  containers:
    - name: sandboxed
      image: busybox:1.36
      command: ["sleep", "infinity"]
```

```bash
kubectl -n ch33-sandbox exec sandboxed -- uname -r      # 4.19.0-gvisor
kubectl -n ch33-sandbox exec sandboxed -- dmesg | head -2
```
