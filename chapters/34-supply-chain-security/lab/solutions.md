# Chapter 34 lab: solutions

Each task has other valid answers; the checks look at the result, not at the
commands.

## Task 1: Only images from the trusted registry

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: ch34-trusted-images
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
  validations:
    - expression: "object.spec.containers.all(c, c.image.startsWith('registry.kbook.example/')) && (!has(object.spec.initContainers) || object.spec.initContainers.all(c, c.image.startsWith('registry.kbook.example/')))"
      message: "Images must come from registry.kbook.example"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: ch34-trusted-images-binding
spec:
  policyName: ch34-trusted-images
  validationActions: ["Deny"]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: ch34-supply
```

The slash at the end of the prefix matters: without it,
`registry.kbook.example.evil.test/...` would pass. `has(object.spec.initContainers)`
guards the second half, because a Pod without init containers has no such field. Test
with a server-side dry run:

```bash
kubectl -n ch34-supply run t --image=nginx:1.27 --dry-run=server
```

## Task 2: Only images pinned by digest

Add a second entry under `validations` of the same policy:

```yaml
    - expression: "object.spec.containers.all(c, c.image.contains('@sha256:')) && (!has(object.spec.initContainers) || object.spec.initContainers.all(c, c.image.contains('@sha256:')))"
      message: "Images must be pinned by digest"
```

Both validations must hold, so an image must come from the trusted registry and be
pinned.

## Task 3: Record the digest the runner Pod runs

```bash
kubectl -n ch34-supply get pod runner -o jsonpath='{.status.containerStatuses[0].imageID}'
```

The `imageID` is `docker.io/library/busybox@sha256:...`; the file takes only the part
after `@`:

```bash
id=$(kubectl -n ch34-supply get pod runner -o jsonpath='{.status.containerStatuses[0].imageID}')
echo "${id##*@}" > /tmp/ch34-digest.txt
```

## Task 4: Fix what static analysis finds

Scan the Deployment as the cluster has it:

```bash
kubectl -n ch34-scan get deployment report -o yaml > report.yaml
trivy config --quiet --severity HIGH,CRITICAL report.yaml
```

The findings name the settings: host networking (KSV-0009), the privileged container
(KSV-0017), the writable root file system (KSV-0014), and the default security context
(KSV-0118). One patch fixes them all:

```bash
kubectl -n ch34-scan patch deployment report -p '{"spec":{"template":{"spec":{
  "hostNetwork":false,
  "securityContext":{"runAsNonRoot":true,"runAsUser":10001,"runAsGroup":10001,"seccompProfile":{"type":"RuntimeDefault"}},
  "containers":[{"name":"report","securityContext":{"privileged":false,"allowPrivilegeEscalation":false,
    "readOnlyRootFilesystem":true,"capabilities":{"drop":["ALL"]}}}]}}}}'
kubectl -n ch34-scan rollout status deployment report
kubectl -n ch34-scan get deployment report -o yaml > report.yaml
trivy config --quiet --severity HIGH,CRITICAL --exit-code 1 report.yaml && echo clean
```

`sleep` writes nothing and needs no privileges, so the hardened Pods run as before. A
real application may need an `emptyDir` for the directories it writes to (Chapter 35).

## Task 5: Remove the Pods with critical vulnerabilities

List each Pod's image, then scan each image for CRITICAL findings only:

```bash
kubectl -n ch34-scan get pods -l scan=me -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}'
for image in nginx:1.19 httpd:2.4.46 alpine:3.20 registry.k8s.io/pause:3.10; do
  trivy image --quiet --skip-db-update --severity CRITICAL --exit-code 1 "$image" >/dev/null && echo "$image clean" || echo "$image CRITICAL"
done
```

With the database of November 2026, `nginx:1.19` (Debian 10) and `httpd:2.4.46` both
have dozens of CRITICAL findings; `alpine:3.20` and the `pause` image have none. A newer
database may report differently, which is why the check scans again with the same
database.

```bash
printf 'legacy-proxy\nlegacy-web\n' > /tmp/ch34-critical.txt
kubectl -n ch34-scan delete pod legacy-proxy legacy-web
```

In practice the answer to such a finding is a newer image, not only a deleted Pod: the
workload that needed nginx should run a supported version.

## Task 6: Sign one image

```bash
cd /tmp
COSIGN_PASSWORD= cosign generate-key-pair --output-key-prefix ch34-cosign
COSIGN_PASSWORD= cosign sign --yes --key ch34-cosign.key --use-signing-config=false --tlog-upload=false localhost:5034/ch34/app:1.0
cosign verify --key ch34-cosign.pub --insecure-ignore-tlog=true localhost:5034/ch34/app:1.0
cosign verify --key ch34-cosign.pub --insecure-ignore-tlog=true localhost:5034/ch34/app:1.1    # Error: no signatures found
```

`--output-key-prefix` names the two files. The signature goes to the registry as an
artifact attached to `app:1.0`'s digest; `app:1.1` is a different digest, with no
signature. Without `--use-signing-config=false --tlog-upload=false`, cosign v3 would also
send the signature to Sigstore's public transparency log, Rekor.
