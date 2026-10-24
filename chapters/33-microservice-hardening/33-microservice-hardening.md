# Chapter 33: Microservice hardening: Pod Security Standards, Secrets, and sandboxed runtimes

> **Exams:** KCNA · KCSA · CKS
> **Difficulty:** Advanced
> **Time:** ~60 min reading, ~45 min lab
> **Lab tier:** 2 (VirtualBox VMs, `envs/vagrant`, snapshot `cluster`)
> **Prerequisites:** Chapter 07 (Secrets), Chapter 10 (securityContext), Chapter 20 (etcdctl), Chapter 29 (the security model), Chapter 31 (admission and Pod Security Admission)

## Learning objectives

After this chapter you can:

- Say what the `baseline` and `restricted` Pod Security Standards forbid, and write a Pod spec that passes `restricted`
- Find the Pods in a Namespace that a Pod Security level would reject, before you enforce it
- Explain why a Deployment can exist while none of its Pods do, and find the reason
- Consume a Secret with as little exposure as possible: as a read-only file, without a ServiceAccount token the Pod does not need
- Turn on encryption at rest for Secrets, rewrite the existing ones, and prove in etcd that it worked
- Choose an isolation technique for a workload, from Namespaces to a sandboxed runtime, and run a Pod under gVisor with a RuntimeClass

## Concepts

Chapter 29 placed these controls on the map: the *Container* layer and the
*Cluster* layer's admission control. This chapter builds them on the Tier 2 VMs,
where you can reach the API server's files, etcd, and the container runtime. All
output below comes from the VMs at Kubernetes v1.37.0.

### Pod Security Standards

The **Pod Security Standards** define three levels for the security-relevant parts
of a Pod spec. They are cumulative: `restricted` contains everything `baseline`
forbids, and more.

| Level | Meant for | What it forbids |
| --- | --- | --- |
| **privileged** | System and infrastructure workloads you trust | Nothing |
| **baseline** | Ordinary workloads; blocks known privilege escalations | Host namespaces (`hostNetwork`, `hostPID`, `hostIPC`), `privileged`, adding capabilities beyond a small default set, `hostPath` volumes, host ports, unsafe sysctls, custom `/proc` mounts, disabling seccomp, AppArmor, or SELinux |
| **restricted** | Security-critical workloads; current hardening practice | All of baseline, plus: volumes other than `configMap`, `secret`, `emptyDir`, `projected`, `downwardAPI`, `persistentVolumeClaim`, `csi`, `ephemeral`; privilege escalation allowed; running as root; no seccomp profile; capabilities not dropped to `ALL` (only `NET_BIND_SERVICE` may be added back) |

The standards are only a definition. **Pod Security Admission**, the admission
controller built into the API server, applies them per Namespace through labels
(Chapter 31):

| Label | Effect on a Pod that violates the level |
| --- | --- |
| `pod-security.kubernetes.io/enforce: <level>` | Rejected |
| `pod-security.kubernetes.io/warn: <level>` | Admitted, with a warning to the client |
| `pod-security.kubernetes.io/audit: <level>` | Admitted, with an annotation in the audit log |
| `pod-security.kubernetes.io/<mode>-version: v1.37` | Pins the rules of that release (default: `latest`) |

### Check before you enforce

Enforcing a level never touches Pods that already run; it only rejects new ones.
To see which running Pods a level would reject, label the Namespace in a **server
dry run**: the API server answers with a warning for each violating Pod and stores
nothing. In a Namespace with a privileged Pod, a Pod in the host's network, and a
plain one:

```bash
kubectl label --dry-run=server --overwrite namespace ch33-demo pod-security.kubernetes.io/enforce=baseline
```

```text
Warning: existing pods in namespace "ch33-demo" violate the new PodSecurity enforce level "baseline:latest"
Warning: hostnet: host namespaces
Warning: priv: privileged
namespace/ch33-demo labeled (server dry run)
```

The plain Pod passes `baseline`. Against `restricted`, every Pod fails, the plain
one too:

```bash
kubectl label --dry-run=server --overwrite namespace ch33-demo pod-security.kubernetes.io/enforce=restricted
```

```text
Warning: existing pods in namespace "ch33-demo" violate the new PodSecurity enforce level "restricted:latest"
Warning: hostnet: host namespaces, allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
Warning: plain: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
Warning: priv: privileged, allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/ch33-demo labeled (server dry run)
```

> **Exam tip:** `kubectl label --dry-run=server` on a Namespace is the fastest way to answer "which Pods would violate level X?". The warnings name each Pod and each reason.

### Enforcing `restricted`

With the label set for real (pinned to v1.37), a Pod that sets nothing is rejected,
and the message lists every field it must set:

```bash
kubectl label namespace ch33-demo pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=v1.37
kubectl -n ch33-demo run test --image=busybox:1.36 -- sleep infinity
```

```text
Error from server (Forbidden): pods "test" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "test" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "test" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "test" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "test" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
```

Pod Security Admission checks **Pods**. A Deployment is not a Pod, so it is created
with only a warning, and then its ReplicaSet fails to create any Pod:

```bash
kubectl create deployment legacy -n ch33-demo --image=busybox:1.36 -- sleep infinity
kubectl -n ch33-demo get deployment legacy
```

```text
Warning: would violate PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "busybox" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "busybox" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "busybox" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "busybox" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/legacy created
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
legacy   0/1     0            0           21s
```

The reason is in the Namespace's events, not on any Pod:

```bash
kubectl -n ch33-demo get events --field-selector reason=FailedCreate -o custom-columns=MESSAGE:.message | head -2
```

```text
MESSAGE
Error creating: pods "legacy-7884c4fdf9-hx8tf" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "busybox" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "busybox" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "busybox" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "busybox" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
```

The smallest spec that passes `restricted` sets four things:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: compliant
  namespace: ch33-demo
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "infinity"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
```

`runAsNonRoot`, the user, and the seccomp profile may sit in the Pod's
`securityContext` (for every container) or in a container's. The privilege
escalation and capability settings exist only per container. `runAsUser: 1000` is
needed here because `busybox` runs as root by default: `runAsNonRoot` alone only
makes the kubelet refuse to start it. An image whose Dockerfile sets a non-root
`USER` needs only `runAsNonRoot: true`.

> **Exam tip:** Learn the four `restricted` settings by heart: `runAsNonRoot: true`, `seccompProfile.type: RuntimeDefault`, `allowPrivilegeEscalation: false`, and `capabilities.drop: ["ALL"]`. The rejection message lists them too, if you forget one.

### Managing Secrets

Chapter 07 showed how to create and consume Secrets. Hardening them is about
exposure: who and what can see the value.

- **Files, not environment variables.** Environment variables are inherited by every child process, often end up in crash dumps and debug output, and are visible in the container's `/proc`. A Secret mounted as a volume is a file you can restrict with `defaultMode` (for example `0400`) and read only where needed. Mounted Secrets also follow updates; environment variables do not.
- **No token where none is needed.** Every Pod gets its ServiceAccount's token mounted by default, even when the app never talks to the API server:

  ```bash
  kubectl -n ch33-demo exec compliant -- ls /var/run/secrets/kubernetes.io/serviceaccount
  ```

  ```text
  ca.crt
  namespace
  token
  ```

  `automountServiceAccountToken: false`, in the Pod spec or on the ServiceAccount, removes it. An attacker in the container then has no identity for the API server.
- **RBAC on Secrets.** `get` on Secrets reads them; `list` and `watch` read all of them in the Namespace at once. And, as Chapter 29 showed, anyone who can create Pods in a Namespace can mount its Secrets.
- **External secret stores.** HashiCorp Vault and the cloud providers' secret managers keep the value outside the cluster; the External Secrets Operator or the Secrets Store CSI Driver bring it in at runtime. That moves the problem to the store's access control, which is often stronger.

### Encryption at rest

By default, the API server stores Secrets in etcd **unencrypted**. Base64 in the
API is an encoding, not protection. With `etcdctl` (installed as in Chapter 20) you
can read a Secret straight out of etcd:

```bash
kubectl -n ch33-demo create secret generic demo-secret --from-literal=password=s3cr3t
sudo etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
  get /registry/secrets/ch33-demo/demo-secret | hexdump -C | head -4
```

```text
00000000  2f 72 65 67 69 73 74 72  79 2f 73 65 63 72 65 74  |/registry/secret|
00000010  73 2f 63 68 33 33 2d 64  65 6d 6f 2f 64 65 6d 6f  |s/ch33-demo/demo|
00000020  2d 73 65 63 72 65 74 0a  6b 38 73 00 0a 0c 0a 02  |-secret.k8s.....|
00000030  76 31 12 06 53 65 63 72  65 74 12 d7 01 0a b8 01  |v1..Secret......|
```

The value starts with `k8s` and a zero byte: the plain protobuf encoding, readable
by anyone with etcd's client certificate or a copy of its data or backups. (The
rest of the dump, further down, contains `s3cr3t` in clear text.)

**Encryption at rest** makes the API server encrypt resources before it writes them
to etcd. It reads an **EncryptionConfiguration** file:

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
              secret: <32 random bytes, base64>
      - identity: {}
```

The **first** provider in the list encrypts everything written from now on; every
provider in the list is tried for reading. `identity` (no encryption) stays at the
end so that the Secrets written before the change can still be read. The key is 32
random bytes, base64-encoded: `head -c 32 /dev/urandom | base64`.

| Provider | Encryption | Note |
| --- | --- | --- |
| `identity` | None | The default; only useful as a reader of old data |
| `aescbc` | AES-CBC | Widely used; the key sits in the file on the control plane node |
| `aesgcm` | AES-GCM | Fast, but the key must be rotated often |
| `secretbox` | XSalsa20 and Poly1305 | Strong; the key sits in the file too |
| `kms` (v2) | Envelope encryption | The key-encryption key stays in an external KMS; the recommended choice in production |

To turn it on, save the file (mode `0600`, here `/etc/kubernetes/enc/enc.yaml`), and
change the API server's static Pod manifest in three places: the flag, a volume, and
its mount. On the VMs:

```bash
sudo diff /tmp/kube-apiserver.yaml.orig /etc/kubernetes/manifests/kube-apiserver.yaml
```

```text
14a15
>     - --encryption-provider-config=/etc/kubernetes/enc/enc.yaml
81a83,85
>     - mountPath: /etc/kubernetes/enc
>       name: enc
>       readOnly: true
103a108,111
>   - hostPath:
>       path: /etc/kubernetes/enc
>       type: DirectoryOrCreate
>     name: enc
```

The kubelet restarts the API server when the manifest changes; wait until
`kubectl get --raw /readyz` answers again. Then look at etcd again. The **old**
Secret is unchanged, and a **new** one is encrypted:

```text
00000020  2d 73 65 63 72 65 74 0a  6b 38 73 00 0a 0c 0a 02  |-secret.k8s.....|
```

```text
00000020  73 65 63 72 65 74 0a 6b  38 73 3a 65 6e 63 3a 61  |secret.k8s:enc:a|
00000030  65 73 63 62 63 3a 76 31  3a 6b 65 79 31 3a 5d 47  |escbc:v1:key1:]G|
```

The prefix `k8s:enc:aescbc:v1:key1:` names the provider and the key. Existing
Secrets are encrypted only when they are written again, so rewrite all of them:

```bash
kubectl get secrets -A -o json | kubectl replace -f - | tail -3
```

```text
secret/new-secret replaced
secret/bootstrap-token-dej4mj replaced
secret/bootstrap-token-qlj6ak replaced
```

Now `demo-secret` carries the prefix as well, and the API still returns its value
unchanged (`czNjcjN0`, base64 for `s3cr3t`): encryption at rest is invisible to
clients.

> **Exam tip:** Two steps are easy to forget: the volume and mount for the configuration file (the API server runs in a container and cannot see the host's files otherwise), and rewriting the existing Secrets. Check the result in etcd, not with `kubectl`, which always shows the decrypted value.

### Isolation techniques

Running many tenants (teams, customers, or untrusted code) on one cluster needs
isolation at several levels:

| Technique | Isolates | Chapter |
| --- | --- | --- |
| Namespaces with RBAC and quotas | Names, permissions, resource consumption | 06, 10, 23 |
| NetworkPolicies | Traffic | 21, 36 |
| Pod Security `restricted` | What a Pod may do on its node | this chapter |
| Dedicated nodes (taints, tolerations, node affinity) | Which tenants share a kernel | 17 |
| Sandboxed runtimes | The kernel itself | this chapter |
| Separate clusters | Everything, including the control plane | 29 |

Every container on a node shares that node's kernel. A kernel vulnerability, or a
container escape, crosses every boundary above the kernel. **Sandboxed runtimes**
put another boundary in between:

- **gVisor** runs each Pod on its own user-space kernel (the *Sentry*), which implements the Linux system calls itself and uses only a small set of the host's. Its runtime is `runsc`.
- **Kata Containers** runs each Pod in a lightweight virtual machine with its own guest kernel.

Both cost something: gVisor slows down system-call-heavy workloads and does not
implement every system call; Kata needs virtualization support and more memory per
Pod. Use them for untrusted or multi-tenant workloads, not by default.

A **RuntimeClass** connects a Pod to a runtime the nodes have configured. Its
`handler` names the runtime in the container runtime's configuration. On the VMs,
the workers' containerd configuration has a `runsc` runtime:

```bash
ssh node1 sudo tail -3 /etc/containerd/config.toml
```

```text

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runsc]
  runtime_type = 'io.containerd.runsc.v1'
```

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
```

A Pod asks for it with `runtimeClassName: gvisor`. Compare a sandboxed Pod with a
normal one in the same Namespace:

```bash
kubectl -n ch33-sbx exec sandboxed -- dmesg | head -3
kubectl -n ch33-sbx exec sandboxed -- uname -r
kubectl -n ch33-sbx exec normal -- uname -r
```

```text
[   0.000000] Starting gVisor...
[   0.495822] Creating process schedule...
[   0.949349] Accelerating teletypewriter to 9600 baud...
4.19.0-gvisor
5.15.0-91-generic
```

The sandboxed Pod talks to gVisor's kernel (whose `dmesg` lines are its own, partly
humorous, invention); the normal Pod sees the node's real kernel. If a RuntimeClass
names a handler that a node does not have, Pods using it fail to start there; the
RuntimeClass's `scheduling` field can restrict them to the nodes that do.

> **Exam tip:** For "run this Pod in a sandbox": create (or find, with `kubectl get runtimeclass`) the RuntimeClass whose handler is `runsc`, set `runtimeClassName` in the Pod spec, and check with `uname -r` or `dmesg` inside the Pod.

### Workload and application code security

The rest of the container layer is about what is in the image and how it runs:
images built to run as a non-root `USER`, without a shell or package manager when
they do not need one, scanned and signed (Chapter 34); a read-only root file
system (Chapter 10); no Secrets baked into images or environment variables; and
dependencies kept up to date. Pod Security `restricted` enforces how a container
runs, not what it contains.

## Hands-on lab

The lab works like a KodeKloud lab, one task at a time with a check after each,
on the Tier 2 VMs, from the `cluster` snapshot:

```bash
cd /kbook
make lab CH=33        # checks you are on cluster, installs gVisor and etcdctl, shows task 1
make check CH=33      # check the current task; if it is right, show the next
make question CH=33   # show the current task again
make verify CH=33     # check every task at once
```

`make lab` installs gVisor (`runsc`) on `node1` and `node2` and adds the `runsc`
runtime to their containerd configuration, and installs `etcdctl` on `cp1`. Work
on `cp1`, with `sudo` for the API server's files and for `etcdctl`. Task 4 changes
the API server, and gVisor stays on the workers: to start over, restore `cluster`
on the host (`make reset CH=33` prints the command). The tasks are independent.
Full solutions are in [`lab/solutions.md`](lab/solutions.md).

### Task 1: Find the Pods that break baseline

The Namespace `ch33-legacy` runs several Pods. Find those that the `baseline`
level rejects, write their names to a file, then enforce `baseline` on the
Namespace and warn about `restricted`.

- File: `/tmp/ch33-violations.txt`, the names of the violating Pods, one per line, sorted alphabetically, nothing else
- Namespace `ch33-legacy`: label `pod-security.kubernetes.io/enforce=baseline` and `pod-security.kubernetes.io/warn=restricted`

### Task 2: Run a Deployment under restricted

The Namespace `ch33-apps` enforces `restricted`. Its Deployment `worker` has no Pods.
Make its Pods pass, without changing the Namespace.

- Deployment `worker` in `ch33-apps`: 2 ready replicas
- The Namespace still enforces `restricted`

### Task 3: Consume a Secret safely

In `ch33-apps`, create a Pod `api` (image `busybox:1.36`, command `sleep infinity`)
that uses the existing Secret `db-pass` as a file and has no API credentials.

- The Secret `db-pass` mounted at `/etc/db`, with file mode `0400`
- No environment variable comes from a Secret
- No ServiceAccount token is mounted
- The Pod is Running (the Namespace enforces `restricted`)

### Task 4: Encrypt Secrets at rest

Make the API server encrypt Secrets in etcd with `aescbc`, and encrypt the Secrets
that already exist in `ch33-apps`.

- The configuration file: `/etc/kubernetes/enc/enc.yaml`, provider `aescbc` first with a key named `key1`
- The Secret `db-pass` is stored in etcd with the prefix `k8s:enc:aescbc:v1:key1:`, and the API still returns its original value

### Task 5: Run a Pod in a sandbox

The workers have gVisor's `runsc` runtime. Make it available to Pods, and run one in it.

- RuntimeClass `gvisor` with the handler `runsc`
- Pod `sandboxed` in `ch33-sandbox`: image `busybox:1.36`, command `sleep infinity`, runtime class `gvisor`, Running, and its kernel is gVisor's (`uname -r` ends in `gvisor`)

## Exam tips

> **Exam tip:** Pod Security Admission rejects Pods, not Deployments. When a Deployment shows `0/N` and no Pods exist, look at `kubectl get events` or `kubectl describe replicaset` for `FailedCreate`.
>
> **Exam tip:** Edit the API server's manifest carefully: copy it out of `/etc/kubernetes/manifests` first (not into that directory, where the kubelet would start the copy as well), and watch `crictl ps` until the API server is back. A typo leaves you without an API.
>
> **Exam tip:** For encryption at rest, prove it with `etcdctl get ... | hexdump -C`. The value must start with `k8s:enc:<provider>:v1:<key name>:`.

## Common misconceptions

- "Base64 is encryption." It is an encoding; anyone can decode it.
- "Enabling encryption at rest encrypts all Secrets." Only those written afterwards. Rewrite the existing ones.
- "Enforcing `restricted` stops running Pods." It only rejects new Pods, including the ones a Deployment creates on its next rollout or restart.
- "`runAsNonRoot: true` makes the container run as a non-root user." It only refuses to start a container whose user is root; the image or `runAsUser` must choose a non-root user.
- "A sandboxed runtime is a stronger version of `restricted`." They work at different levels: Pod Security limits what a Pod may ask for, a sandbox limits what a compromised container can reach in the kernel. Use both for untrusted code.
- "Namespaces isolate tenants." They separate names and anchor RBAC and quotas; traffic, nodes, and the kernel are still shared until you add policies, dedicated nodes, or sandboxes.

<!-- QUESTIONS:START -->

## End-of-chapter questions

**1.** `KCNA` `KCSA` `CKS` Which are the three Pod Security Standards, from the most to the least permissive?

- **A.** privileged, baseline, restricted
- **B.** open, default, locked
- **C.** restricted, baseline, privileged
- **D.** permissive, enforced, audited

**2.** `KCSA` `CKS` A Pod mounts a hostPath volume and sets nothing else. Which levels does it pass?

- **A.** privileged, baseline, and restricted
- **B.** privileged only
- **C.** privileged and baseline
- **D.** None

**3.** `KCSA` `CKS` What does the label pod-security.kubernetes.io/warn=restricted do on a Namespace?

- **A.** Rejects Pods that violate restricted
- **B.** Records violations in the audit log only
- **C.** Deletes running Pods that violate restricted
- **D.** Admits violating Pods, and returns a warning to the client that created them

**4.** `CKS` How do you find the running Pods of a Namespace that the baseline level would reject, without changing anything?

- **A.** kubectl label --dry-run=server --overwrite namespace NS pod-security.kubernetes.io/enforce=baseline
- **B.** kubectl get pods -n NS --show-labels
- **C.** kubectl auth can-i create pods -n NS
- **D.** kubectl label --dry-run=client namespace NS pod-security.kubernetes.io/enforce=baseline

**5.** `CKS` A Namespace enforces restricted. You create a Deployment whose Pod template sets no securityContext. What happens?

- **A.** The Deployment is rejected
- **B.** The Deployment is created with a warning, but its ReplicaSet fails to create any Pod
- **C.** The Pods are created and run as privileged
- **D.** Pod Security Admission adds the missing settings

**6.** `CKS` Which set of settings makes a busybox container (which runs as root by default) pass restricted?

- **A.** privileged: false and readOnlyRootFilesystem: true
- **B.** runAsNonRoot: true only
- **C.** runAsNonRoot: true, runAsUser: 1000, seccompProfile RuntimeDefault, allowPrivilegeEscalation: false, capabilities drop ALL
- **D.** hostNetwork: false and runAsGroup: 1000

**7.** `KCSA` `CKS` Why is mounting a Secret as a file usually safer than putting it in an environment variable?

- **A.** Files are encrypted inside the container
- **B.** Environment variables are visible to the API server
- **C.** Files cannot be read by root
- **D.** Environment variables are inherited by child processes and leak into dumps and debug output; a file can have restrictive permissions and is read only where needed

**8.** `CKS` Which setting stops Kubernetes from mounting a ServiceAccount token into a Pod?

- **A.** serviceAccountName: none
- **B.** automountServiceAccountToken: false, on the Pod or its ServiceAccount
- **C.** readOnlyRootFilesystem: true
- **D.** runAsNonRoot: true

**9.** `KCSA` `CKS` You add an EncryptionConfiguration with aescbc first and identity second, and the API server restarts with it. Which Secrets are now encrypted in etcd?

- **A.** All Secrets, at once
- **B.** Only Secrets in kube-system
- **C.** Only Secrets written from now on; existing ones stay unencrypted until they are written again
- **D.** None, until etcd restarts

**10.** `CKS` How do you prove that a Secret is encrypted at rest?

- **A.** kubectl get secret NAME -o yaml shows encrypted data
- **B.** kubectl describe secret NAME shows the provider
- **C.** The Secret's data is base64-encoded
- **D.** Read it from etcd with etcdctl: the stored value starts with k8s:enc:PROVIDER:v1:KEY-NAME:

**11.** `KCSA` `CKS` What does gVisor add between a container and the node?

- **A.** A user-space kernel that handles the container's system calls, so the container does not use the host kernel directly
- **B.** A full virtual machine with its own guest kernel for every container
- **C.** A firewall for the container's traffic
- **D.** Encryption of the container's file system

**12.** `KCSA` `CKS` What does the handler field of a RuntimeClass name?

- **A.** The node the Pods must run on
- **B.** The image the Pods must use
- **C.** The runtime configured in the container runtime on the nodes, such as runsc for gVisor
- **D.** The admission plugin that checks the Pods

**13. (Task)** `CKS` In a Namespace that enforces restricted, run a Pod that reads the Secret app-key from a file in mode 0400, has no ServiceAccount token, and runs as user 1000.

<details>
<summary>Answers</summary>

**1. A.** privileged allows everything, baseline blocks known privilege escalations (host namespaces, privileged containers, hostPath, and more), and restricted adds current hardening practice on top (non-root, seccomp, all capabilities dropped, no privilege escalation).

**2. B.** baseline forbids hostPath volumes, and restricted contains everything baseline forbids. Only privileged, which forbids nothing, admits the Pod.

**3. D.** warn admits the Pod and warns the client; audit admits it and annotates the audit event; enforce rejects it. None of the modes touches Pods that already run.

**4. A.** A server dry run makes Pod Security Admission evaluate the existing Pods against the new level and return a warning for each violator, without storing the label. A client dry run never reaches the API server, so it cannot.

**5. B.** Pod Security Admission checks Pods. The Deployment and the ReplicaSet are stored (with a warning), and every Pod the ReplicaSet tries to create is rejected; the reason appears in FailedCreate events. Pod Security Admission validates, it never mutates.

**6. C.** restricted needs non-root, a seccomp profile, no privilege escalation, and all capabilities dropped. runAsNonRoot alone would make the kubelet refuse to start an image whose user is root, so runAsUser must pick a non-root user.

**7. D.** Environment variables spread: to every child process, to /proc, to crash reports. A mounted Secret is a file with a mode such as 0400, and it also follows updates to the Secret.

**8. B.** By default every Pod gets a projected token for its ServiceAccount. automountServiceAccountToken: false removes it; a compromised container then has no credentials for the API server.

**9. C.** The first provider encrypts new writes; identity lets the API server still read the old, unencrypted values. Rewrite the existing Secrets (kubectl get secrets -A -o json | kubectl replace -f -) to encrypt them.

**10. D.** The API always returns the decrypted value, base64-encoded as usual. Only the raw value in etcd shows whether the API server encrypted it, and with which provider and key.

**11. A.** gVisor's Sentry implements the Linux system calls in user space and uses only a small set of the host's. Kata Containers is the one that runs each Pod in a lightweight virtual machine.

**12. C.** A Pod with runtimeClassName uses the RuntimeClass's handler, which must match a runtime the nodes' containerd or CRI-O has configured. If a node lacks it, the Pod fails to start there; the RuntimeClass's scheduling field can restrict such Pods to nodes that have it.

**13.**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: reader
spec:
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  volumes:
    - name: key
      secret:
        secretName: app-key
        defaultMode: 0400
  containers:
    - name: reader
      image: busybox:1.36
      command: ["sleep", "infinity"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
      volumeMounts:
        - name: key
          mountPath: /etc/key
          readOnly: true
```

The four restricted settings let the Pod in; the volume's defaultMode sets the file mode, and automountServiceAccountToken removes the token. Mode 0400 leaves the file readable by root only; add fsGroup and mode 0440 if user 1000 must read it.

</details>

<!-- QUESTIONS:END -->
