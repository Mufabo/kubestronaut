# Chapter 24 lab: solutions

Try each task before reading its solution. The commands below pass
`-n ch24-crd` explicitly, because the lab does not change your default namespace.

## Task 1: create the Backup CRD

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.ch24.example.com
spec:
  group: ch24.example.com
  scope: Namespaced
  names:
    plural: backups
    singular: backup
    kind: Backup
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required: [schedule, target]
              properties:
                schedule:
                  type: string
                target:
                  type: string
YAML
kubectl wait --for=condition=Established crd/backups.ch24.example.com --timeout=120s
```

The CRD is cluster-scoped. The wait matters: until `Established`, the server
does not serve the new kind.

## Task 2: a Backup called `nightly`

```bash
cat <<'YAML' | kubectl -n ch24-crd apply -f -
apiVersion: ch24.example.com/v1
kind: Backup
metadata:
  name: nightly
spec:
  schedule: "0 2 * * *"
  target: db
YAML
```

The `apiVersion` is the group and version of the CRD, `ch24.example.com/v1`.

## Task 3: test the schema

```bash
cat <<'YAML' | kubectl -n ch24-crd apply --dry-run=server -f -
apiVersion: ch24.example.com/v1
kind: Backup
metadata:
  name: bad-backup
spec:
  schedule: "0 2 * * *"
YAML
```

The server answers `spec.target: Required value`, so write `rejected`:

```bash
echo rejected > /tmp/ch24-validation.txt
```

A server-side dry run runs the schema without storing the object.

## Task 4: list the Backup objects

```bash
kubectl -n ch24-crd get backups.ch24.example.com -o name > /tmp/ch24-names.txt
```

`-o name` prints `kind/name`, here `backup.ch24.example.com/nightly`.

## Task 5: the container runtime

```bash
kubectl get node kbook-worker -o jsonpath='{.status.nodeInfo.containerRuntimeVersion}' | sed 's#://.*##' > /tmp/ch24-cri.txt
```

The field reads `containerd://2.2.0`. The part before `://` is the runtime's name,
`containerd`, which is what the CRI in this cluster is.

## Task 6: cert-manager issues `site-tls`

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update jetstack
helm install cert-manager jetstack/cert-manager --version v1.21.2 \
  --namespace ch24-cert-manager --create-namespace \
  --set crds.enabled=true --set global.leaderElection.namespace=ch24-cert-manager \
  --wait --timeout 5m
kubectl api-resources --api-group=cert-manager.io
```

```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned
  namespace: ch24-crd
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: site
  namespace: ch24-crd
spec:
  secretName: site-tls
  dnsNames:
    - site.example.test
  issuerRef:
    kind: Issuer
    name: selfsigned
```

```bash
kubectl apply -f site.yaml
kubectl -n ch24-crd wait --for=condition=Ready certificate/site --timeout=120s
kubectl -n ch24-crd get secret site-tls
kubectl -n ch24-crd describe certificate site
```

You write the `Issuer` and the `Certificate`; the operator writes the Secret, and
its events show the private key and the `CertificateRequest` it used. Without
`crds.enabled=true`, the chart installs no CRDs, and the `Issuer` is refused with
"no matches for kind". Without the leader-election setting, the operator keeps
its Leases in `kube-system`.

## Why these checks accept any correct method

The checks read what the API server stores: the CRD's group, kind, scope and
Established condition, the Backup's fields, a server-side dry run of the invalid
object, the list of Backup objects, and the runtime name on the node. You can
create the CRD and the object with any tool, and the checks do not care which.
