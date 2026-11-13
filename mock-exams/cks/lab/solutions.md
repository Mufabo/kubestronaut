# Mock exam CKS: solutions

Read these only after `make mock-score EXAM=cks`. Each entry shows one way to
answer the question; the checks accept any method that leaves the same result.
Every command runs on `cp1` unless it says `ssh`. The chapter in brackets teaches
the topic.

## Question 1: default deny, with one exception (Chapters 21 and 36)

```bash
kubectl config use-context cks-a
kubectl -n cks-shop apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 8080
EOF
API=$(kubectl -n cks-shop get pod api -o jsonpath='{.status.podIP}')
kubectl -n cks-shop exec frontend -- wget -qO- -T 3 http://$API:8080   # api
kubectl -n cks-shop exec other -- wget -qO- -T 3 http://$API:8080      # times out
```

An empty `podSelector` selects every Pod in the Namespace; `policyTypes: [Ingress]`
with no `ingress` rules denies all incoming traffic. Policies add up, so
`api-allow` opens exactly one path. Leaving `Egress` out of both keeps outgoing
traffic open; adding it would also block the frontend's own requests.

## Question 2: genuine binaries (Chapter 30)

```bash
curl -fsSL https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubeadm.sha512
cd /tmp/kbook/cks/2
sha512sum kubeadm-a kubeadm-b kubeadm-c
rm kubeadm-<each one whose sum differs>
```

The release publishes a `.sha512` (and a `.sha256`) next to every binary. Two of
the files were changed by a few bytes at the end, which is enough to change the
whole checksum.

## Question 3: a ServiceAccount with too much power (Chapter 23)

```bash
kubectl delete clusterrolebinding deployer-admin
kubectl -n cks-ci create role deployer --verb=get,list,create,update --resource=deployments.apps
kubectl -n cks-ci create rolebinding deployer --role=deployer --serviceaccount=cks-ci:deployer
kubectl auth can-i create deployments -n cks-ci --as=system:serviceaccount:cks-ci:deployer   # yes
kubectl auth can-i delete deployments -n cks-ci --as=system:serviceaccount:cks-ci:deployer   # no
kubectl auth can-i get secrets -n cks-ci --as=system:serviceaccount:cks-ci:deployer          # no
```

Check `kubectl get clusterrolebindings,rolebindings -A -o wide | grep deployer` too:
any other binding of the ServiceAccount would also have to go.

## Question 4: kubelets may change only what is theirs (Chapters 30 and 31)

The plugin is `NodeRestriction`. In `/etc/kubernetes/manifests/kube-apiserver.yaml`
(copy it out of the directory first):

```yaml
    - --enable-admission-plugins=NodeRestriction
```

The flag was `ServiceAccount`, a plugin that is on by default anyway. Wait for the
API server (`kubectl get --raw /readyz`), then test with node1's own credentials:

```bash
ssh node1 sudo kubectl --kubeconfig /etc/kubernetes/kubelet.conf label node node1 node-restriction.kubernetes.io/test=x --dry-run=server
```

```text
Error from server (Forbidden): nodes "node1" is forbidden: is not allowed to modify labels: node-restriction.kubernetes.io/test
```

Without the plugin, the same command answers `node/node1 labeled (server dry run)`:
a compromised node could give itself the labels that steer sensitive workloads
to it.

## Question 5: AppArmor for a Deployment (Chapter 32)

```bash
ssh node2 grep ^profile /etc/apparmor.d/cks-guard          # profile cks-readonly ...
ssh node2 sudo apparmor_parser /etc/apparmor.d/cks-guard
ssh node2 sudo aa-status | grep cks
kubectl -n cks-sys patch deployment writer -p '{"spec":{"template":{"spec":{"securityContext":{"appArmorProfile":{"type":"Localhost","localhostProfile":"cks-readonly"}}}}}}'
kubectl -n cks-sys rollout status deployment writer
kubectl -n cks-sys exec deploy/writer -- cat /proc/1/attr/current     # cks-readonly (enforce)
```

The file is named `cks-guard`, but the profile inside is `cks-readonly`, and Pods
refer to the profile's name. With `cks-guard` as `localhostProfile`, the new Pods
stay in `CreateContainerError` ("apparmor profile not found").

## Question 6: a seccomp profile (Chapter 32)

```bash
scp /tmp/kbook/cks/6/trace.json node1:/tmp/
ssh node1 sudo install -D -m 0644 /tmp/trace.json /var/lib/kubelet/seccomp/cks/trace.json
kubectl -n cks-sys apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: tracer
spec:
  nodeSelector:
    kubernetes.io/hostname: node1
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: cks/trace.json
  containers:
    - name: tracer
      image: busybox:1.36
      command: ["sleep", "infinity"]
EOF
kubectl -n cks-sys exec tracer -- grep Seccomp: /proc/1/status   # 2
```

`localhostProfile` is relative to `/var/lib/kubelet/seccomp/` on the node that runs
the Pod. This profile only logs (`SCMP_ACT_LOG`), so the container works normally
and every system call it makes is recorded in the node's kernel log.

## Question 7: enforce restricted (Chapter 33)

Fix the Deployment first, then enforce; the other way round, its next rollout
would be rejected:

```bash
kubectl -n cks-pci patch deployment payments -p '{"spec":{"template":{"spec":{
  "securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},
  "containers":[{"name":"payments","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}}}'
kubectl -n cks-pci rollout status deployment payments
kubectl label --overwrite namespace cks-pci pod-security.kubernetes.io/enforce=restricted
kubectl label --dry-run=server --overwrite namespace cks-pci pod-security.kubernetes.io/enforce=restricted   # no warnings
```

`runAsUser: 1000` is needed because busybox runs as root: `runAsNonRoot` alone
would make the kubelet refuse to start it.

## Question 8: encrypt Secrets with secretbox (Chapter 33)

```bash
sudo mkdir -p /etc/kubernetes/enc
sudo tee /etc/kubernetes/enc/cks.yaml <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - secretbox:
          keys:
            - name: cks-key
              secret: $(head -c 32 /dev/urandom | base64)
      - identity: {}
EOF
sudo chmod 600 /etc/kubernetes/enc/cks.yaml
```

In the API server's manifest: the flag, and a volume with its mount:

```yaml
    - --encryption-provider-config=/etc/kubernetes/enc/cks.yaml
    # ...
    volumeMounts:
    - mountPath: /etc/kubernetes/enc
      name: enc
      readOnly: true
    # ...
  volumes:
  - hostPath:
      path: /etc/kubernetes/enc
      type: DirectoryOrCreate
    name: enc
```

When the API server is back, rewrite the existing Secrets and look in etcd:

```bash
kubectl -n cks-pci get secrets -o json | kubectl replace -f -
sudo etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
  get /registry/secrets/cks-pci/card-keys | hexdump -C | head -3    # k8s:enc:secretbox:v1:cks-key:
```

## Question 9: a sandbox for untrusted code (Chapter 33)

```bash
kubectl apply -f - <<'EOF'
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: sandboxed
handler: runsc
EOF
kubectl -n cks-sbx patch deployment untrusted -p '{"spec":{"template":{"spec":{"runtimeClassName":"sandboxed"}}}}'
kubectl -n cks-sbx rollout status deployment untrusted
kubectl -n cks-sbx exec deploy/untrusted -- uname -r     # ...-gvisor
```

## Question 10: no latest images (Chapters 31 and 34)

```bash
kubectl config use-context cks-b
kubectl apply -f - <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: cks-no-latest
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["deployments"]
  validations:
    - expression: >-
        object.spec.template.spec.containers.all(c,
          c.image.contains('@sha256:') ||
          (c.image.substring(c.image.lastIndexOf('/') + 1).contains(':') &&
           !c.image.endsWith(':latest')))
      message: "images must name a tag other than latest, or a digest"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: cks-no-latest
spec:
  policyName: cks-no-latest
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: cks-prod
EOF
kubectl create deployment t --image=nginx --dry-run=server           # denied
kubectl create deployment t --image=nginx:1.27 --dry-run=server      # allowed
```

The tag is what follows the last `:` after the last `/`: looking only for a `:`
anywhere would let `registry.example.com:5000/app` through untagged. A digest
reference contains `@sha256:`. Every Namespace carries the label
`kubernetes.io/metadata.name`, which makes it easy to select one by name.

## Question 11: pin an image by digest (Chapter 34)

```bash
kubectl get pods -l app=cache -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'
kubectl set image deployment/cache nginx=nginx@sha256:<the digest>
kubectl rollout status deployment cache
```

The Pod's `imageID` is the digest the node actually pulled for `nginx:1.27`. The
policy from question 10, if it is already there, lets the digest through.

## Question 12: harden a Dockerfile (Chapter 34)

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
RUN useradd --uid 10001 --no-create-home appuser
USER appuser
CMD ["python", "app.py"]
```

`latest` is not a version: the image changes under you. A token in `ENV` is baked
into the image, visible to anyone who can pull it (`docker history`, `docker
inspect`); it belongs in a Secret at runtime. And the process should not run as
root: create a user and switch to it before `CMD`.

## Question 13: audit what matters (Chapter 35)

```bash
sudo mkdir -p /etc/kubernetes/audit /var/log/kubernetes/audit
sudo tee /etc/kubernetes/audit/cks-policy.yaml <<'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
  - RequestReceived
rules:
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets"]
  - level: RequestResponse
    namespaces: ["cks-prod"]
    verbs: ["create", "update", "patch", "delete"]
    resources:
      - group: "apps"
        resources: ["deployments"]
  - level: None
EOF
```

In the API server's manifest:

```yaml
    - --audit-policy-file=/etc/kubernetes/audit/cks-policy.yaml
    - --audit-log-path=/var/log/kubernetes/audit/cks.log
    - --audit-log-maxage=5
    - --audit-log-maxbackup=3
    # ...
    volumeMounts:
    - mountPath: /etc/kubernetes/audit/cks-policy.yaml
      name: audit-policy
      readOnly: true
    - mountPath: /var/log/kubernetes/audit
      name: audit-log
    # ...
  volumes:
  - hostPath:
      path: /etc/kubernetes/audit/cks-policy.yaml
      type: File
    name: audit-policy
  - hostPath:
      path: /var/log/kubernetes/audit
      type: DirectoryOrCreate
    name: audit-log
```

Questions 4, 8, and 13 all edit the same manifest; doing them in one edit saves
two restarts of the API server.

## Question 14: who reads /etc/sudoers? (Chapter 35)

```bash
ssh node1 "sudo journalctl -u falco-modern-bpf --no-pager -o cat | grep sudoers | tail -1"
```

The alert (`Sensitive file opened for reading by non-trusted program`) ends with
`k8s_pod_name=...` and `k8s_ns_name=...`:

```bash
echo <namespace>/<pod> > /tmp/kbook/cks/14/culprit.txt
kubectl -n <namespace> delete pod <pod>
```

The four Pods' commands are base64-encoded, so their specs look alike; the
behavior gives the culprit away. In a real incident you would quarantine the Pod
first and keep it for the investigation (Chapter 35).

## Question 15: an immutable web server (Chapter 35)

```bash
kubectl -n cks-run patch deployment site -p '{"spec":{"template":{"spec":{"containers":[{"name":"httpd","securityContext":{"readOnlyRootFilesystem":true}}]}}}}'
kubectl -n cks-run get pods -l app=site        # the new Pods fail
```

httpd writes its PID file to `/usr/local/apache2/logs`, and fails to start without
it. Give it an `emptyDir` there:

```bash
kubectl -n cks-run patch deployment site -p '{"spec":{"template":{"spec":{
  "volumes":[{"name":"logs","emptyDir":{}}],
  "containers":[{"name":"httpd","volumeMounts":[{"name":"logs","mountPath":"/usr/local/apache2/logs"}]}]}}}}'
kubectl -n cks-run rollout status deployment site
kubectl -n cks-run exec deploy/site -- touch /usr/local/apache2/htdocs/x   # Read-only file system
```
