# Chapter 35 lab: solutions

Every command runs on `cp1`; `node1` is reached with `ssh node1`. Each task has
other valid answers; the checks look at the result, not at the commands. The
misbehaving Deployment in Task 2 is chosen when the lab starts, so yours may
differ from `billing`.

## Task 1: Turn on audit logging

The policy. The rules are checked in order and the first match decides, so the
two specific rules come before the catch-all `None`:

```bash
sudo mkdir -p /etc/kubernetes/audit /var/log/kubernetes/audit
sudo tee /etc/kubernetes/audit/policy.yaml <<'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
  - RequestReceived
rules:
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets", "configmaps"]
  - level: RequestResponse
    namespaces: ["ch35-apps"]
    resources:
      - group: ""
        resources: ["pods"]
  - level: None
EOF
```

Then the API server's manifest. Copy it out first (not into `manifests/`, where
the kubelet would run the copy too), and edit `/etc/kubernetes/manifests/kube-apiserver.yaml`
in three places:

```yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --audit-policy-file=/etc/kubernetes/audit/policy.yaml
    - --audit-log-path=/var/log/kubernetes/audit/audit.log
    - --audit-log-maxage=7
    - --audit-log-maxbackup=2
    - --audit-log-maxsize=50
    # ... the existing flags ...
    volumeMounts:
    - mountPath: /etc/kubernetes/audit/policy.yaml
      name: audit-policy
      readOnly: true
    - mountPath: /var/log/kubernetes/audit
      name: audit-log
    # ... the existing mounts ...
  volumes:
  - hostPath:
      path: /etc/kubernetes/audit/policy.yaml
      type: File
    name: audit-policy
  - hostPath:
      path: /var/log/kubernetes/audit
      type: DirectoryOrCreate
    name: audit-log
  # ... the existing volumes ...
```

The kubelet restarts the API server; wait until `kubectl get --raw /readyz`
answers `ok`. Then test the policy: a ConfigMap read is logged at `Metadata`, a
ServiceAccount read not at all:

```bash
kubectl -n ch35-apps get configmap kube-root-ca.crt
sudo grep kube-root-ca.crt /var/log/kubernetes/audit/audit.log | grep ch35-apps | tail -1
```

The last line's `"level":"Metadata"`, `"stage":"ResponseComplete"`, `"verb":"get"`,
and the user `kubernetes-admin` are the request you just made. Without
`omitStages`, each request would appear twice, once for `RequestReceived`.

## Task 2: Find the Pod that reads /etc/shadow

Falco's default rule `Read sensitive file untrusted` has caught it:

```bash
ssh node1 "sudo journalctl -u falco-modern-bpf --no-pager -o cat | grep shadow | tail -1"
```

```text
19:53:53.524226926: Warning Sensitive file opened for reading by non-trusted program | file=/etc/shadow gparent=sh ggparent=containerd-shim gggparent=systemd evt_type=openat user=root user_uid=0 user_loginuid=-1 process=cat proc_exepath=/bin/cat parent=sh command=cat /etc/shadow terminal=0 container_id=10b58f6106b2 container_name=worker container_image_repository=docker.io/library/busybox container_image_tag=1.36 k8s_pod_name=billing-5868dc47b9-6l27w k8s_ns_name=ch35-apps
```

The Pod's owner is a ReplicaSet, whose owner is the Deployment:

```bash
kubectl -n ch35-apps get pod billing-5868dc47b9-6l27w -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
```

```text
ReplicaSet/billing-5868dc47b9
```

```bash
echo billing > /tmp/ch35-falco.txt
kubectl -n ch35-apps scale deployment billing --replicas=0
```

The three Deployments' commands are base64-encoded on purpose: the Pod specs all
look alike, and the behavior is what gives the culprit away. Deleting the Pod
would not help, because its ReplicaSet starts a new one; in a real incident you
would quarantine it first (Task 5) to keep the evidence.

## Task 3: Write a Falco rule

```bash
ssh node1 "sudo tee /etc/falco/rules.d/ch35-rules.yaml" <<'EOF'
- rule: Write below etc in container
  desc: A process in a container opened a file below /etc for writing
  condition: open_write and container and fd.name startswith /etc/
  output: File below /etc opened for writing (file=%fd.name command=%proc.cmdline)
  priority: WARNING
EOF
ssh node1 sudo falco -V /etc/falco/falco_rules.yaml -V /etc/falco/rules.d/ch35-rules.yaml
ssh node1 sudo systemctl restart falco-modern-bpf
```

`open_write` and `container` are macros from the default rules, which is why the
validation loads both files. After a few seconds, trigger it:

```bash
kubectl -n ch35-apps exec canary -- sh -c ': >> /etc/group'
ssh node1 "sudo journalctl -u falco-modern-bpf --no-pager -o cat | grep 'below /etc' | tail -1"
```

```text
19:56:21.700169714: Warning File below /etc opened for writing (file=/etc/group command=sh -c : >> /etc/group) container_id=ac1f15e5d5f2 container_name=canary container_image_repository=docker.io/library/busybox container_image_tag=1.36 k8s_pod_name=canary k8s_ns_name=ch35-apps
```

`: >> /etc/group` opens the file for appending and writes nothing, so it changes
nothing in the container, but the `open` system call is enough for the rule.

## Task 4: Make web immutable

With only `readOnlyRootFilesystem: true`, the new Pods crash, and the log says
why:

```bash
kubectl -n ch35-apps get pods -l app=web
kubectl -n ch35-apps logs web-dc76765cc-jbzbm --previous | tail -1
```

```text
NAME                   READY   STATUS             RESTARTS     AGE
web-85fc769995-5rgkf   1/1     Running            0            49s
web-dc76765cc-jbzbm    0/1     CrashLoopBackOff   1 (2s ago)   7s
web-dc76765cc-k2lzh    1/1     Running            0            4s
nginx: [emerg] mkdir() "/var/cache/nginx/client_temp" failed (30: Read-only file system)
```

(The rollout stops there, so one old Pod keeps serving.) Give nginx `emptyDir`
volumes for its cache and for its PID file in `/var/run`:

```bash
kubectl -n ch35-apps edit deployment web
```

```yaml
    spec:
      volumes:
        - name: cache
          emptyDir: {}
        - name: run
          emptyDir: {}
      containers:
        - name: nginx
          image: nginx:1.27
          securityContext:
            readOnlyRootFilesystem: true
          volumeMounts:
            - name: cache
              mountPath: /var/cache/nginx
            - name: run
              mountPath: /var/run
```

```bash
kubectl -n ch35-apps rollout status deployment web
kubectl -n ch35-apps exec deploy/web -- touch /usr/share/nginx/html/x
```

```text
touch: cannot touch '/usr/share/nginx/html/x': Read-only file system
command terminated with exit code 1
```

## Task 5: Quarantine miner

Label the Pod, then select it with a policy that has both types and no rules:

```bash
kubectl -n ch35-apps label pod miner status=quarantined
kubectl -n ch35-apps apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: quarantine
spec:
  podSelector:
    matchLabels:
      status: quarantined
  policyTypes:
    - Ingress
    - Egress
EOF
kubectl -n ch35-apps describe networkpolicy quarantine | tail -7
```

```text
Spec:
  PodSelector:     status=quarantined
  Allowing ingress traffic:
    <none> (Selected pods are isolated for ingress connectivity)
  Allowing egress traffic:
    <none> (Selected pods are isolated for egress connectivity)
  Policy Types: Ingress, Egress
```

`miner` keeps running, so its processes, files, and logs stay available for the
investigation, but it can no longer reach `web`, the API server, or the
internet, and nothing can reach it. A selector on `app=miner` would also work for
this one Pod, but the label states the Pod's status and can be put on any other
Pod that turns out to be compromised.
