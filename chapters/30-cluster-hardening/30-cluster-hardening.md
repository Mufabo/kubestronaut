# Chapter 30: Cluster setup hardening: the CIS Benchmark, kube-bench, and the control plane's flags

> **Exams:** KCSA · CKS
> **Difficulty:** Advanced
> **Time:** ~60 min reading, ~45 min lab
> **Lab tier:** 2 (VirtualBox VMs, `envs/vagrant`, snapshot `cluster`)
> **Prerequisites:** Chapter 18 (kubeadm and its files), Chapter 27 (static Pods and certificates), Chapter 29 (the security model)

## Learning objectives

After this chapter you can:

- Say how the CIS Kubernetes Benchmark is organized, and what an Automated or Manual recommendation means
- Run kube-bench against a control plane and a worker with the right benchmark, read its results, and decide which findings to fix and which to document
- Harden the API server, controller manager, scheduler, kubelet, and etcd through their flags and configuration files
- Restrict who and what can reach the Kubernetes API, and explain what anonymous requests may still do
- Keep kubeadm's admin credentials safe, and tell `admin.conf` from `super-admin.conf`
- Block Pods from the cloud metadata endpoint, and verify Kubernetes binaries against the published checksums

## Concepts

A kubeadm cluster starts reasonably safe, but not hardened: some settings favor
convenience or compatibility. This chapter checks the cluster against the
**CIS Kubernetes Benchmark**, fixes what matters, and covers the hardening the
benchmark does not do for you. Everything runs on the Tier 2 VMs at v1.37.0,
where the control plane's files are within reach.

### The CIS Kubernetes Benchmark

The Center for Internet Security publishes the benchmark: a few hundred
recommendations, each with a rationale, an **audit** (how to check it), and a
**remediation** (how to fix it). Its sections follow the cluster's components:

| Section | Covers |
| --- | --- |
| 1 Control plane | 1.1 file permissions and ownership of manifests and PKI, 1.2 API server, 1.3 controller manager, 1.4 scheduler |
| 2 etcd | TLS for clients and peers, certificate authentication |
| 3 Control plane configuration | Authentication methods, audit logging |
| 4 Worker nodes | 4.1 kubelet files, 4.2 kubelet configuration, 4.3 kube-proxy |
| 5 Policies | RBAC, ServiceAccounts, Pod Security, NetworkPolicies, Secrets, Namespaces |

Each recommendation is **Automated** (a tool can check it) or **Manual** (a person
must judge it), and **Level 1** (sensible everywhere) or **Level 2** (defense in
depth, may cost functionality). A benchmark version targets a range of Kubernetes
versions.

### kube-bench

**kube-bench** (from Aqua Security) runs the benchmark's audits on a node and
reports each recommendation as PASS, FAIL, WARN (manual, or could not be checked),
or INFO. It reads files and running processes on the node it runs on, so run it on
the control plane node for the control plane checks and on each worker for the node
checks. The lab installs v0.16.0, with its benchmark definitions in
`/etc/kube-bench/cfg`.

kube-bench chooses the benchmark from the cluster's version, which it asks the API
server for. As root, without a kubeconfig, it cannot, and it says so:

```bash
sudo kube-bench run --targets master 2>&1 | head -3
```

```text
Warning: Kubernetes version was not auto-detected because kubectl could not connect to the Kubernetes server. This may be because the kubeconfig information is missing or has credentials that do not match the server. Assuming default version 1.18
Warning: Kubernetes version was not auto-detected because kubectl could not connect to the Kubernetes server. This may be because the kubeconfig information is missing or has credentials that do not match the server. Assuming default version 1.18
[INFO] 1 Master Node Security Configuration
```

Version 1.18 means a benchmark from 2020. Name the benchmark yourself:
`--benchmark cis-1.12`, the newest one kube-bench v0.16.0 ships (its mapping ends at
Kubernetes 1.34, and the recommendations still apply to 1.37). The warning stays, but
the checks are now the right ones:

```bash
sudo kube-bench run --targets master --benchmark cis-1.12 2>&1 | grep -E "^\[FAIL\]|^== Summary|checks (PASS|FAIL|WARN|INFO)"
```

```text
[FAIL] 1.1.12 Ensure that the etcd data directory ownership is set to etcd:etcd (Automated)
[FAIL] 1.2.5 Ensure that the --kubelet-certificate-authority argument is set as appropriate (Automated)
[FAIL] 1.2.15 Ensure that the --profiling argument is set to false (Automated)
[FAIL] 1.2.16 Ensure that the --audit-log-path argument is set (Automated)
[FAIL] 1.2.17 Ensure that the --audit-log-maxage argument is set to 30 or as appropriate (Automated)
[FAIL] 1.2.18 Ensure that the --audit-log-maxbackup argument is set to 10 or as appropriate (Automated)
[FAIL] 1.2.19 Ensure that the --audit-log-maxsize argument is set to 100 or as appropriate (Automated)
[FAIL] 1.2.30 Ensure that the --service-account-extend-token-expiration parameter is set to false (Automated)
[FAIL] 1.3.2 Ensure that the --profiling argument is set to false (Automated)
[FAIL] 1.4.1 Ensure that the --profiling argument is set to false (Automated)
== Summary master ==
39 checks PASS
10 checks FAIL
11 checks WARN
0 checks INFO
== Summary total ==
39 checks PASS
10 checks FAIL
11 checks WARN
0 checks INFO
```

Thirty-nine passes: kubeadm already sets most of what the benchmark asks (RBAC,
NodeRestriction, TLS everywhere, restrictive file permissions on the PKI). The ten
failures fall into three groups, and not all of them should be "fixed":

| Findings | What to do |
| --- | --- |
| 1.2.15, 1.3.2, 1.4.1: profiling is on | Fix. Profiling exposes `/debug/pprof` endpoints that leak internals and can be used to load the component; production does not need it. |
| 1.2.16 to 1.2.19: no audit log | Fix, with an audit policy: Chapter 35. |
| 1.1.12, 1.2.5, 1.2.30 | Judge and document. kubeadm runs etcd as root, with no `etcd` user; `--kubelet-certificate-authority` only works once kubelets serve certificates signed by the cluster CA (server certificate rotation, approved by an admin or a controller); the token-expiration setting exists for migrating old clients. |

A benchmark is a list of recommendations, not orders. Fix what applies, and write
down why the rest does not, with the compensating control: that record is what an
audit asks for (Chapter 29).

For each finding, kube-bench prints the benchmark's remediation:

```bash
sudo kube-bench run --targets master --benchmark cis-1.12 --check 1.2.15 2>/dev/null | sed -n '/== Remediations/,/^$/p'
```

```text
== Remediations master ==
1.2.15 Edit the API server pod specification file /etc/kubernetes/manifests/kube-apiserver.yaml
on the control plane node and set the below parameter.
--profiling=false
```

After adding `- --profiling=false` to the manifest's `command` and waiting for the
API server to come back, the check passes:

```bash
sudo kube-bench run --targets master --benchmark cis-1.12 --check 1.2.15 2>/dev/null | grep -E '^\[(PASS|FAIL)\]'
```

```text
[PASS] 1.2.15 Ensure that the --profiling argument is set to false (Automated)
```

kube-bench reads the flags of the running processes. Run it when the control plane
has settled: during a restart of the API server, the controller manager and the
scheduler can restart too, and their checks then fail for no lasting reason.

### The worker nodes

On a worker, the node checks look at the kubelet's files and configuration. On
`node2`:

```bash
ssh node2 "sudo kube-bench run --targets node --benchmark cis-1.12 2>/dev/null | grep -E '^\[FAIL\]|checks FAIL'"
```

```text
[FAIL] 4.1.1 Ensure that the kubelet service file permissions are set to 600 or more restrictive (Automated)
[FAIL] 4.1.9 If the kubelet config.yaml configuration file is being used validate permissions set to 600 or more restrictive (Automated)
2 checks FAIL
2 checks FAIL
```

Both are file permissions (`644` on the VMs). Which files? The audit says. A
`chmod 600` on kubeadm's drop-in (`/usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf`)
and on `/var/lib/kubelet/config.yaml` leaves one failure:

```bash
ssh node2 "sudo kube-bench run --targets node --benchmark cis-1.12 2>/dev/null | grep -E 'checks (PASS|FAIL|WARN)'"
```

```text
18 checks PASS
1 checks FAIL
6 checks WARN
18 checks PASS
1 checks FAIL
6 checks WARN
```

because 4.1.1 checks the kubelet's own unit file. The `audit` field of each result
in `--json` output names the command (shown here with the check's number, its status,
and the value it found):

```text
4.1.1 FAIL /bin/sh -c 'if test -e /lib/systemd/system/kubelet.service; then stat -c permissions=%a /lib/systemd/system/kubelet.service; fi'  => permissions=644
4.1.9 PASS /bin/sh -c 'if test -e /var/lib/kubelet/config.yaml; then stat -c permissions=%a /var/lib/kubelet/config.yaml; fi'  => permissions=600
```

> **Exam tip:** When a kube-bench finding does not go away, read its audit command (`--json`, or the benchmark file in `cfg/`). It names exactly the file or flag it checks, which may not be the one you changed.

### The API server

The API server's flags decide who gets in and what happens to requests. The ones the
benchmark and the exams care about:

| Flag | Hardened value | Why |
| --- | --- | --- |
| `--anonymous-auth` | `false`, or limited to health endpoints | Requests without credentials become `system:anonymous` |
| `--authorization-mode` | `Node,RBAC` (never `AlwaysAllow`) | kubeadm's default |
| `--enable-admission-plugins` | includes `NodeRestriction` | A kubelet may only change its own Node and its own Pods (kubeadm's default) |
| `--profiling` | `false` | No debug endpoints |
| `--audit-log-path`, `--audit-policy-file` | set | A record of who did what (Chapter 35) |
| `--encryption-provider-config` | set | Secrets encrypted in etcd (Chapter 33) |
| `--tls-min-version`, `--tls-cipher-suites` | `VersionTLS12` or `13`; strong suites only | No weak TLS |
| `--kubelet-certificate-authority` | the cluster CA | The API server verifies the kubelets it calls |

**Restricting access to the API** starts below these flags. Put the API server on a
private network or behind a firewall that admits only known sources; never expose it
through a NodePort or LoadBalancer Service. Then know what an unauthenticated client
can still do. kubeadm leaves anonymous requests on, so that health checks and
discovery work, and RBAC grants them very little:

```bash
curl -sk https://192.168.56.10:6443/version | head -5
curl -sk https://192.168.56.10:6443/api/v1/namespaces | head -8
```

```text
{
  "major": "1",
  "minor": "37",
  "emulationMajor": "1",
  "emulationMinor": "37",
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "namespaces is forbidden: User \"system:anonymous\" cannot list resource \"namespaces\" in API group \"\" at the cluster scope",
  "reason": "Forbidden",
  "details": {
```

The version is public (the `system:public-info-viewer` ClusterRole); anything else
needs credentials. Turning anonymous auth off entirely breaks probes that call the API
server without credentials, so check the manifest's liveness and readiness probes
before you do it; never bind a role to `system:anonymous` or `system:unauthenticated`.

### The controller manager and the scheduler

Both run as static Pods on the control plane with their own kubeconfigs. The
benchmark wants them to listen only on localhost (`--bind-address=127.0.0.1`,
kubeadm's default), with profiling off, and the controller manager to use a separate
ServiceAccount per controller (`--use-service-account-credentials=true`, also the
default). The same `--profiling=false` fixes 1.3.2 and 1.4.1.

### The kubelet

The kubelet's API on port 10250 can list Pods, read logs, and run commands in
containers on its node. kubeadm configures it safely in `/var/lib/kubelet/config.yaml`:
anonymous requests off, authorization delegated to the API server (`Webhook`), and
the unauthenticated read-only port 10255 closed. From `cp1`:

```bash
curl -sk https://node1:10250/pods
curl -s -m 3 http://node1:10255/pods; echo rc=$?
```

```text
Unauthorized
rc=7
```

On a kubelet configured carelessly, with `authentication.anonymous.enabled: true`,
`authorization.mode: AlwaysAllow`, and `readOnlyPort: 10255`, the same requests
return every Pod on the node, specs and environment included, to anyone on the
network:

```text
{"kind":"PodList","apiVersion":"v1","metadata":{},"items":[{"metadata":{"name":"kube-proxy-xd8qr","generateName":"kube-proxy-","namespace":"kube-system","uid":"
{"kind":"PodList","apiVersion":"v1","metadata":{},"items":[{"metadata":{"name":"calico-node-h5vd2","generateName":"calico-node-","namespace":"kube-system","uid"
```

The hardened settings, and two more worth having:

```yaml
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
authorization:
  mode: Webhook
readOnlyPort: 0
rotateCertificates: true
protectKernelDefaults: true
```

After a change, `sudo systemctl restart kubelet` on that node. Port 10250 must still
be reachable from the API server (for `logs` and `exec`), but from nowhere else.

### etcd

etcd holds every object, Secrets included. kubeadm configures it with client
certificate authentication (`--client-cert-auth=true`) and TLS for clients and peers,
listening on localhost and the node's address. What remains for you: only the API
server (and backup tooling) should reach port 2379 (firewall), its data directory and
backups need strict permissions and encryption (Chapters 20 and 33), and peer traffic
on 2380 should stay between etcd members.

### PKI and client security

kubeadm's certificates (Chapters 18 and 27) protect every connection; renew them before
they expire and keep the CA keys on the control plane only. The kubeconfig files in
`/etc/kubernetes` are credentials, readable by root only:

```bash
sudo ls -l /etc/kubernetes/*.conf
```

```text
-rw------- 1 root root 5637 Oct 23 16:57 /etc/kubernetes/admin.conf
-rw------- 1 root root 5665 Oct 23 16:57 /etc/kubernetes/controller-manager.conf
-rw------- 1 root root 1941 Oct 23 16:57 /etc/kubernetes/kubelet.conf
-rw------- 1 root root 5609 Oct 23 16:57 /etc/kubernetes/scheduler.conf
-rw------- 1 root root 5661 Oct 23 16:57 /etc/kubernetes/super-admin.conf
```

Two of them are admin credentials, with an important difference:

```bash
sudo grep client-certificate-data /etc/kubernetes/admin.conf | awk '{print $2}' | base64 -d | openssl x509 -noout -subject
sudo grep client-certificate-data /etc/kubernetes/super-admin.conf | awk '{print $2}' | base64 -d | openssl x509 -noout -subject
```

```text
subject=O = kubeadm:cluster-admins, CN = kubernetes-admin
subject=O = system:masters, CN = kubernetes-super-admin
```

`admin.conf` is in the group `kubeadm:cluster-admins`, which a ClusterRoleBinding
makes cluster admin: delete the binding, and the credential loses its power.
`super-admin.conf` is in `system:masters`, which bypasses RBAC entirely and cannot be
revoked short of replacing the CA. Keep it offline for emergencies. People get their
own identities (client certificates via CSRs with short expirations, or an OIDC
provider), not copies of `admin.conf`.

### Protecting node metadata and endpoints

Chapter 29 explained why Pods must not reach the cloud's metadata endpoint. A
NetworkPolicy that selects every Pod of a Namespace can allow all egress except that
address:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-metadata
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 169.254.169.254/32
```

Because it allows the rest, DNS and Services keep working. The node's own endpoints
need the same thought: the kubelet (10250), etcd (2379, 2380), and the control plane's
ports belong behind host or cloud firewall rules, and NodePorts open ports on every
node.

### Verifying platform binaries

A tampered `kubectl`, `kubelet`, or `kubeadm` defeats every other control. The
Kubernetes release publishes a SHA-512 checksum next to each binary on `dl.k8s.io`:

```bash
curl -fsSLO https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl
curl -fsSLO https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl.sha512
echo "$(cat kubectl.sha512)  kubectl" | sha512sum --check
```

```text
kubectl: OK
```

A copy with a single extra byte fails:

```text
kubectl-bad: FAILED
sha512sum: WARNING: 1 computed checksum did NOT match
```

To check a binary already installed, compare `sha512sum /usr/bin/kubelet` with the
published checksum of that exact version and platform. Packages from `pkgs.k8s.io` are
signed, and apt verifies them with the repository's key (Chapter 18). Container images
get the same treatment with signatures and digests (Chapter 34).

> **Exam tip:** Checksum questions are quick points: download the `.sha512` for the exact version and architecture, and compare. A mismatch means the binary must not be used.

### Ingress with TLS

The CKS also asks for Ingress objects with TLS: a `kubernetes.io/tls` Secret with the
certificate and key, and a `tls` section in the Ingress that names it and its hosts.
Chapter 12 builds one (Task 2); together with an HTTP-to-HTTPS redirect in the
controller, it keeps traffic from the internet to the cluster encrypted.

## Hands-on lab

The lab works like a KodeKloud lab, one task at a time with a check after each,
on the Tier 2 VMs, from the `cluster` snapshot:

```bash
cd /kbook
make lab CH=30        # checks you are on cluster, installs kube-bench, prepares the tasks
make check CH=30      # check the current task; if it is right, show the next
make question CH=30   # show the current task again
make verify CH=30     # check every task at once
```

`make lab` installs kube-bench v0.16.0 on `cp1` and `node2` (run it with
`--benchmark cis-1.12`), loosens the kubelet on `node1` the way a careless admin
might, and puts three `kubectl` binaries in `/opt/ch30`. Work on `cp1`, with `sudo`
for the control plane's files and `ssh node1`, `ssh node2` for the workers. Task 2
changes the control plane: to start over, restore `cluster` on the host
(`make reset CH=30` prints the command). The tasks are independent. Full solutions
are in [`lab/solutions.md`](lab/solutions.md).

### Task 1: Pass kube-bench's node checks on node2

Run kube-bench's node checks on `node2` and fix what fails.

- `sudo kube-bench run --targets node --benchmark cis-1.12` on `node2` reports no FAIL

### Task 2: Turn off profiling on the control plane

Fix CIS findings 1.2.15, 1.3.2, and 1.4.1.

- The API server, controller manager, and scheduler run with `--profiling=false`
- All three are Running and ready

### Task 3: Harden node1's kubelet

The kubelet on `node1` accepts anonymous requests, allows everything, and serves the
read-only port. Close all three.

- In `node1`'s `/var/lib/kubelet/config.yaml`: anonymous authentication off, authorization mode `Webhook`, read-only port off
- An anonymous request to `https://node1:10250/pods` gets `Unauthorized`, and nothing answers on port 10255
- `node1` is Ready

### Task 4: Keep only the genuine kubectl

`/opt/ch30` holds three files named like `kubectl-<letter>`. Only one is the
official `kubectl` v1.37.0 for linux/amd64.

- `/opt/ch30` contains only the binary that matches the published SHA-512 checksum of `kubectl` v1.37.0; the others are deleted

### Task 5: Keep Pods away from the metadata endpoint

In `ch30-apps`, Pods must not reach `169.254.169.254`, and everything else must keep
working.

- NetworkPolicy `deny-metadata` in `ch30-apps`: selects every Pod, egress only, allows all addresses except `169.254.169.254/32`
- The Pod `client` still reaches the Service `web` by name

## Exam tips

> **Exam tip:** Always pass `--benchmark` (or `--version`) to kube-bench when you run it as root. Without it, it may silently check against a years-old benchmark.
>
> **Exam tip:** Static Pod manifests take effect when you save them. Back up the file outside `/etc/kubernetes/manifests` first, change one flag at a time, and watch `sudo crictl ps` until the component is back.
>
> **Exam tip:** Kubelet settings live in `/var/lib/kubelet/config.yaml` on each node, not in the API. Edit, then `sudo systemctl restart kubelet`, and test with `curl` from another machine.

## Common misconceptions

- "Every kube-bench FAIL must be fixed." Some findings do not apply or would break the cluster; document them with the reason and the compensating control.
- "A clean kube-bench run means a secure cluster." The benchmark checks configuration; it says nothing about your RBAC grants, images, or exposed Services.
- "`admin.conf` and `super-admin.conf` are the same." `admin.conf`'s group is bound by a ClusterRoleBinding you can delete; `super-admin.conf` is in `system:masters`, which RBAC cannot restrict.
- "The kubelet is only reachable by the API server." Port 10250 listens on the node's address; only authentication, authorization, and the network keep others out.
- "Anonymous auth on means anyone can do anything." It means unauthenticated requests reach authorization as `system:anonymous`, which RBAC grants almost nothing; the danger is a binding someone adds for it.
- "A checksum from the same site as the binary proves nothing." It proves the download was not corrupted or swapped in transit or on a mirror; signed packages and images add proof of origin.

<!-- QUESTIONS:START -->

## End-of-chapter questions

**1.** `KCSA` `CKS` What does a recommendation marked Automated in the CIS Kubernetes Benchmark mean?

- **A.** Kubernetes applies it automatically
- **B.** Its audit can be checked by a tool such as kube-bench; Manual ones need a person's judgment
- **C.** It is mandatory, unlike Manual ones
- **D.** It only applies to managed clusters

**2.** `CKS` You run sudo kube-bench run --targets master on a v1.37 control plane and get a warning that it assumes version 1.18. What do you do?

- **A.** Nothing; the version does not matter
- **B.** Run it without sudo
- **C.** Name the benchmark (for example --benchmark cis-1.12) or the version, so that it checks against current recommendations
- **D.** Upgrade the cluster to 1.18

**3.** `CKS` kube-bench reports FAIL for 1.2.15 (the API server's --profiling). Where do you fix it on a kubeadm cluster?

- **A.** In /etc/kubernetes/manifests/kube-apiserver.yaml, by adding - --profiling=false to the command
- **B.** With kubectl edit deployment kube-apiserver -n kube-system
- **C.** In /var/lib/kubelet/config.yaml on the control plane node
- **D.** In the kubeadm-config ConfigMap only

**4.** `KCSA` `CKS` A kube-bench finding says the etcd data directory should be owned by etcd:etcd, but kubeadm runs etcd as root and there is no etcd user. What is the right response?

- **A.** Create an etcd user and change the ownership anyway
- **B.** Disable the check in kube-bench and forget about it
- **C.** Uninstall etcd
- **D.** Record it as not applicable, with the reason and the compensating controls (restrictive permissions, no other access to the node)

**5.** `KCSA` `CKS` Which kubelet settings stop anyone on the network from listing the node's Pods without credentials?

- **A.** rotateCertificates: true
- **B.** authentication.anonymous.enabled: false, authorization.mode: Webhook, and readOnlyPort: 0
- **C.** protectKernelDefaults: true
- **D.** serializeImagePulls: false

**6.** `KCSA` `CKS` An unauthenticated client sends GET /version and GET /api/v1/namespaces to a kubeadm API server. What happens?

- **A.** Both are rejected with 401
- **B.** Both succeed
- **C.** The version is returned; listing Namespaces is forbidden for system:anonymous
- **D.** The connection is refused

**7.** `KCSA` `CKS` What is the difference between kubeadm's admin.conf and super-admin.conf?

- **A.** admin.conf's identity is in the group kubeadm:cluster-admins, bound to cluster-admin by a ClusterRoleBinding; super-admin.conf's is in system:masters, which bypasses RBAC
- **B.** There is none; super-admin.conf is a backup copy
- **C.** admin.conf has read-only access
- **D.** super-admin.conf can only be used from the control plane node

**8.** `KCSA` `CKS` Which admission plugin limits a kubelet to modifying only its own Node object and the Pods bound to its node?

- **A.** PodSecurity
- **B.** AlwaysPullImages
- **C.** LimitRanger
- **D.** NodeRestriction

**9.** `CKS` How do you check that a downloaded kubelet binary is the official v1.37.0 release for linux/amd64?

- **A.** Run kubelet --version
- **B.** Compare its file size with the one on the website
- **C.** Download kubelet.sha512 for that version and platform from dl.k8s.io and compare it with sha512sum of the binary
- **D.** Check its modification date

**10.** `CKS` A NetworkPolicy selects every Pod in a Namespace, with policyTypes [Egress] and one egress rule to ipBlock 0.0.0.0/0 except 169.254.169.254/32. What is the effect?

- **A.** The Pods can reach any address except the metadata endpoint
- **B.** The Pods can reach only the metadata endpoint
- **C.** All egress is blocked, including DNS
- **D.** Nothing, because ipBlock only applies to ingress

**11.** `CKS` After you fix the kubeadm drop-in's permissions, kube-bench still fails 4.1.1 (kubelet service file permissions). What is the most likely reason?

- **A.** kube-bench caches old results
- **B.** The check audits another file, the kubelet's own unit file; its audit command names it
- **C.** The kubelet must be restarted first
- **D.** 4.1.1 can never pass on kubeadm clusters

**12.** `KCSA` `CKS` Which statement about restricting access to the Kubernetes API is true?

- **A.** RBAC alone is enough; the API server can be exposed to the internet safely
- **B.** Exposing the API server through a NodePort Service is the recommended pattern
- **C.** Anonymous auth must always be on so that kubectl works
- **D.** Combine network controls (private endpoint, firewall) with authentication and RBAC; do not expose the API server more than necessary

**13. (Task)** `CKS` On a kubeadm control plane node, check whether the scheduler runs with profiling disabled, and fix it if not.

<details>
<summary>Answers</summary>

**1. B.** Automated means the audit can be checked by a tool, not that the setting is applied for you or that it is mandatory. Manual recommendations need judgment; kube-bench reports them as WARN.

**2. C.** As root, kube-bench often cannot reach the API server to detect the version and falls back to an old benchmark. Passing --benchmark (or --version) makes it use the right checks.

**3. A.** The API server is a static Pod: the kubelet runs it from the manifest and restarts it when the file changes. There is no Deployment to edit, and changing kubeadm-config alone affects only future kubeadm operations.

**4. D.** A benchmark is a set of recommendations. Findings that do not fit the deployment are documented with a reason; that record is part of what auditors ask for. Changing ownership alone would not make etcd run as another user.

**5. B.** Anonymous authentication off rejects requests without credentials on port 10250, Webhook makes the API server authorize the rest, and readOnlyPort 0 closes the unauthenticated port 10255. kubeadm sets all three by default.

**6. C.** kubeadm leaves anonymous requests on. They are authenticated as system:anonymous, and RBAC lets that user read only public information such as the version (system:public-info-viewer). Never bind more to system:anonymous.

**7. A.** Removing the kubeadm:cluster-admins binding takes admin.conf's power away. system:masters cannot be restricted by RBAC, so super-admin.conf belongs offline, for emergencies only.

**8. D.** NodeRestriction, together with the Node authorizer, keeps a compromised kubelet from changing other nodes or Pods elsewhere. kubeadm enables it by default; the CIS Benchmark checks for it.

**9. C.** --version prints whatever the binary says, and sizes and dates prove nothing. The published SHA-512 checksum must match exactly; a single changed byte makes it fail.

**10. A.** The rule allows all destinations but the excepted one. Because everything else is allowed, DNS and Services keep working; only 169.254.169.254 becomes unreachable.

**11. B.** Each check runs a specific audit command. On these nodes 4.1.1 stats /lib/systemd/system/kubelet.service, not the kubeadm drop-in. Reading the audit (--json) shows exactly what is checked.

**12. D.** Defense in depth: keep the API server off the public internet, admit only known networks, then authenticate and authorize every request. kubectl uses credentials and does not need anonymous auth.

**13.**

```bash
sudo kube-bench run --targets master --benchmark cis-1.12 --check 1.4.1 2>/dev/null | grep -E '^\[(PASS|FAIL)\]'
sudo cp /etc/kubernetes/manifests/kube-scheduler.yaml /root/kube-scheduler.yaml.bak
sudo vim /etc/kubernetes/manifests/kube-scheduler.yaml      # add: - --profiling=false
sudo crictl ps --name kube-scheduler
kubectl -n kube-system get pod -l component=kube-scheduler -o jsonpath='{.items[0].spec.containers[0].command}'
```

The backup goes outside /etc/kubernetes/manifests: a second manifest there would start a second scheduler.

</details>

<!-- QUESTIONS:END -->
