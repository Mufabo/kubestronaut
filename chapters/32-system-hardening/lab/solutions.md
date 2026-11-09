# Chapter 32 lab: solutions

Every command runs on `cp1`; the workers are reached with `ssh node1` and `ssh
node2`. Each task has other valid answers; the checks look at the result, not at
the commands. The service's name in Task 1 is chosen when the lab starts, so yours
may differ from `print-portal`.

## Task 1: Remove a service nobody needs

Find the process behind the port, then the unit that started it:

```bash
ssh node1 sudo ss -tlnp | grep 8081
```

```text
LISTEN 0      5            0.0.0.0:8081       0.0.0.0:*    users:(("python3",pid=18547,fd=3))
```

```bash
ssh node1 ps -o unit= -p 18547
```

```text
print-portal.service
```

`systemctl status 18547` names the unit too. Stop it and remove it from the boot
targets in one step, then write the answer file and check the port:

```bash
ssh node1 sudo systemctl disable --now print-portal.service
echo print-portal.service > /tmp/ch32-service.txt
ssh node1 "sudo ss -tln 'sport = :8081'"
```

```text
Removed /etc/systemd/system/multi-user.target.wants/print-portal.service.
State Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
```

Only the header is left. `systemctl stop` alone would pass until the next boot,
but the check also wants the unit disabled; `kill` would not help at all, because
the unit restarts its process (`Restart=always`). `systemctl mask` passes as well.

## Task 2: Take sudo away from ops

```bash
ssh node1 "sudo -l -U ops | tail -3; id ops; sudo ls /etc/sudoers.d"
```

```text
User ops may run the following commands on node1:
    (ALL : ALL) ALL
    (ALL) NOPASSWD: ALL
uid=1001(ops) gid=1001(ops) groups=1001(ops),27(sudo)
ops
README
vagrant
```

Two rules give `ops` root: `(ALL : ALL) ALL` comes from the `sudo` group (through
`%sudo` in `/etc/sudoers`), `(ALL) NOPASSWD: ALL` from `/etc/sudoers.d/ops`.
Remove both:

```bash
ssh node1 "sudo rm /etc/sudoers.d/ops; sudo gpasswd -d ops sudo; sudo -l -U ops"
```

```text
Removing user ops from group sudo
User ops is not allowed to run sudo on node1.
```

Deleting the user would also take away its `sudo`, but the task keeps the
account.

## Task 3: Run a Pod under an AppArmor profile

The name Pods use is the one after `profile` in the file. Load it on `node1`:

```bash
ssh node1 "grep ^profile /etc/apparmor.d/kbook-deny-write; sudo apparmor_parser /etc/apparmor.d/kbook-deny-write; sudo aa-status | grep kbook"
```

```text
profile kbook-deny-write flags=(attach_disconnected) {
   kbook-deny-write
```

Then the Pod, pinned to `node1`, the only node with the profile:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: guarded
  namespace: ch32-hardening
spec:
  nodeSelector:
    kubernetes.io/hostname: node1
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: kbook-deny-write
  containers:
    - name: guarded
      image: busybox:1.36
      command: ["sleep", "infinity"]
```

```bash
kubectl -n ch32-hardening exec guarded -- cat /proc/1/attr/current
kubectl -n ch32-hardening exec guarded -- touch /tmp/x
```

```text
kbook-deny-write (enforce)
touch: /tmp/x: Permission denied
command terminated with exit code 1
```

`nodeName: node1` works too. The profile may also sit in the container's
`securityContext`. If you created the Pod before loading the profile, it waits in
`CreateContainerError` and starts on the kubelet's next retry once the profile is
loaded.

## Task 4: Run a Pod under a custom seccomp profile

Copy the profile into the kubelet's seccomp directory on `node1`:

```bash
scp /kbook/chapters/32-system-hardening/manifests/no-chmod.json node1:/tmp/
ssh node1 sudo install -D -m 0644 /tmp/no-chmod.json /var/lib/kubelet/seccomp/profiles/no-chmod.json
```

`localhostProfile` is relative to `/var/lib/kubelet/seccomp`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: locked
  namespace: ch32-hardening
spec:
  nodeSelector:
    kubernetes.io/hostname: node1
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/no-chmod.json
  containers:
    - name: locked
      image: busybox:1.36
      command: ["sleep", "infinity"]
```

```bash
kubectl -n ch32-hardening exec locked -- chmod 1777 /tmp
kubectl -n ch32-hardening exec locked -- grep Seccomp: /proc/1/status
```

```text
chmod: /tmp: Operation not permitted
command terminated with exit code 1
Seccomp:	2
```

`/tmp` already has mode `1777`, so the `chmod` would change nothing; the profile
refuses the system call itself, before the kernel looks at the file.

## Task 5: Make RuntimeDefault the default on node2

Turn on `seccompDefault` in the kubelet's configuration on `node2`, and restart
the kubelet:

```bash
ssh node2 "echo 'seccompDefault: true' | sudo tee -a /var/lib/kubelet/config.yaml; sudo systemctl restart kubelet"
ssh node2 sudo tail -3 /var/lib/kubelet/config.yaml
```

```text
syncFrequency: 0s
volumeStatsAggPeriod: 0s
seccompDefault: true
```

(If the file already had a `seccompDefault` line, change it instead: a second key
in the same YAML file is an error.) The running `plain` keeps the profile it was
created with, so recreate it from its own spec:

```bash
kubectl -n ch32-hardening get pod plain -o yaml > plain.yaml
kubectl replace --force -f plain.yaml
kubectl -n ch32-hardening exec plain -- grep Seccomp: /proc/1/status
```

```text
Seccomp:	2
```

The spec still has no `seccompProfile`; the kubelet chose `RuntimeDefault` for
it. Setting `seccompProfile` in the Pod would also give `Seccomp: 2`, but the task
forbids it, because it is a per-Pod fix, not a node default.
