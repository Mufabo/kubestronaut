# Chapter 24: CRDs, operators, and the extension interfaces (CRI, CNI, CSI)

> **Exams:** KCNA · CKA
> **Difficulty:** Advanced
> **Time:** ~55 min reading, ~35 min lab
> **Lab tier:** 1 (kind)
> **Prerequisites:** Chapter 05 (Controllers), Chapter 13 (Storage), Chapter 21 (Networking internals), Chapter 22 (CSI)

## Learning objectives

After this chapter you can:

- Explain what a CustomResourceDefinition (CRD) adds to the API, and why a custom object is stored and served like a built-in one
- Write a CRD with a group, versions, a scope, and an OpenAPI schema, and create custom objects that the schema accepts or refuses
- Describe the operator pattern: a CRD for the desired state, and a controller that reconciles the cluster toward it
- Install an operator with Helm, configure it through its own custom resources, and watch it reconcile
- Name the three extension interfaces that let Kubernetes work with different runtimes, networks, and storage (CRI, CNI, CSI), and find each one on a running cluster
- Use `kubectl api-resources` and `kubectl explain` to discover custom kinds and their fields
- Recognize a CRD's versions and their storage version, and explain what a version change requires

## Concepts

### Extending the API without changing Kubernetes

The Kubernetes API is a set of resource types, each with a group, a version, and
a kind. Pods, Deployments, and Services are built in. A **CustomResourceDefinition**
(CRD) adds a new type to the same API, without a new release of Kubernetes. After
you create the CRD, the API server serves the new kind at its own path, stores its
objects in etcd, and checks them against a schema. From `kubectl` the new kind
looks like any other.

A CRD names its kind, its group, and its scope. The group is a DNS-style name you
control, such as `backups.example.com`, so that types from different projects do
not collide. The scope is `Namespaced` or `Cluster`, and it decides whether objects
belong to a namespace.

```yaml
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
```

### Versions, the storage version, and the schema

A CRD can serve several versions of its kind at once, such as `v1alpha1` and `v1`.
Exactly one version is the **storage version**: the API server writes objects in
that version to etcd. The others are converted on the way in and out. Each version
has its own schema, and `served: true` decides whether clients may use it.

The schema is an OpenAPI v3 description. It can require fields, limit their types
and ranges, and reject unknown fields. The API server enforces it on every create
and update, so a Backup with no `target` is refused with an error that names the
field:

```text
The Backup "bad-backup" is invalid: spec.target: Required value
```

Schemas are the reason a CRD is safer than a ConfigMap with a convention: the
cluster refuses the bad object, instead of a controller discovering it later.

### Custom objects

A custom object is a normal object with the CRD's group and version in its
`apiVersion`. You can create it, read it, label it, delete it, and watch it. RBAC
applies to it like any resource, using the group and the plural name (Chapter 23).
`kubectl api-resources` lists every kind the cluster serves, including custom
kinds, and `kubectl explain` reads the schema, so a custom kind documents itself.

### The operator pattern

A CRD on its own only stores data. It becomes useful when a **controller** acts on
it. That pairing is an **operator**: a CRD describes the desired state, such as
"nightly backups of this database", and a controller, running as a Deployment in
the cluster, watches those objects and makes the real world match them. It creates
the Jobs, Services, or volumes the desired state needs, and writes what it observed
back to the object's status.

This is the same reconciliation loop as the built-in controllers in Chapter 05:
observe the desired state, compare it with the actual state, act on the difference,
and repeat. The only new part is that the desired state is a type you defined.

An operator therefore has two parts you can check separately: the CRD, which the
API server enforces, and the controller, which must be running for the object to
do anything. A custom object with no controller is valid and inert.

Real operators are installed like any cluster component, usually with Helm, and
bring several CRDs at once. You then configure them through their custom
resources, not through flags. **cert-manager** is a good first one: an `Issuer`
says where certificates come from, and a `Certificate` says which certificate you
want and in which Secret to keep it. The operator does the rest, and renews the
certificate before it expires. Two details are typical of operators:

- Their charts keep the CRDs when the release is uninstalled, because deleting a
  CRD deletes every object of its kind. Removing the CRDs is a separate,
  deliberate step.
- Their controllers use leader election, with Leases in a Namespace you can
  choose. Keep them in the operator's own Namespace rather than `kube-system`.

### The three extension interfaces

Kubernetes does not run containers, wire up the network, or create disks itself.
It calls three interfaces, and each one has a standard that lets different
implementations plug in:

- **CRI (Container Runtime Interface).** The kubelet talks to a container runtime
  through gRPC: containerd, CRI-O, and others. The kubelet asks the runtime to pull
  images, start containers, and report their status. Check it with
  `containerRuntimeVersion` in a node's `status.nodeInfo`, which shows the runtime
  name before `://`.
- **CNI (Container Network Interface).** A plugin gives each Pod its network and
  routes. Its configuration is a file in `/etc/cni/net.d` on each node, as Chapter
  21 showed. The lab cluster uses Calico, and its file is `10-calico.conflist`.
- **CSI (Container Storage Interface).** A driver creates, attaches, and mounts
  volumes. It registers a CSIDriver object, as Chapter 22 showed. The lab cluster
  has none.

These interfaces are how Kubernetes stays the same across clouds and laptops. A
cluster's choices of runtime, network, and storage show up as the files, objects,
and version strings you can read on the nodes.

## Guided walkthrough

The walkthrough works in the Namespace `ch24-demo`. The outputs below are trimmed:
ages, versions, and IDs differ on your cluster. The walkthrough creates its own CRD,
`widgets.demo.example.com`, so it does not touch the lab's CRD. The lab later in this
chapter uses the namespace `ch24-crd`. Create the demo namespace with
`kubectl create namespace ch24-demo`.

### Create a CRD and wait for it

Apply a CRD with a required integer field, then wait until the API serves it:

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.demo.example.com
spec:
  group: demo.example.com
  scope: Namespaced
  names:
    plural: widgets
    singular: widget
    kind: Widget
    shortNames: [wg]
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
              required: [size]
              properties:
                size:
                  type: integer
                  minimum: 1
YAML
kubectl wait --for=condition=Established crd/widgets.demo.example.com --timeout=60s
```

```text
customresourcedefinition.apiextensions.k8s.io/widgets.demo.example.com created
customresourcedefinition.apiextensions.k8s.io/widgets.demo.example.com condition met
```

`Established` means the API server has started serving the new kind. Until then,
creating an object of that kind fails.

### Discover the new kind

```bash
kubectl api-resources --api-group=demo.example.com
```

```text
NAME      SHORTNAMES   APIVERSION            NAMESPACED   KIND
widgets   wg           demo.example.com/v1   true         Widget
```

The new kind has a short name, `wg`, which the CRD declared, and it is namespaced.

### Create a valid object and refuse an invalid one

Create a Widget that satisfies the schema, then ask the server to accept one that does not:

```bash
cat <<'YAML' | kubectl -n ch24-demo apply -f -
apiVersion: demo.example.com/v1
kind: Widget
metadata:
  name: blue
spec:
  size: 3
YAML
kubectl -n ch24-demo get wg
cat <<'YAML' | kubectl -n ch24-demo apply --dry-run=server -f - 2>&1 | tail -1
apiVersion: demo.example.com/v1
kind: Widget
metadata:
  name: green
spec:
  size: 0
YAML
```

```text
widget.demo.example.com/blue created
NAME   AGE
blue   0s
The Widget "green" is invalid: spec.size: Invalid value: 0: spec.size in body should be greater than or equal to 1
```

The schema's minimum is enforced by the API server. A server-side dry run tests
the rule without storing anything, which is how you check a schema before you use it.

### Read the schema with explain

```bash
kubectl explain widget.spec --api-version=demo.example.com/v1
```

```text
GROUP:      demo.example.com
KIND:       Widget
VERSION:    v1

FIELD: spec <Object>

FIELDS:
  size	<integer> -required-
```

`explain` reads the same schema the server enforces. A field marked `-required-` is
the one the server checks.

### Look at the three extension interfaces on this cluster

Find the runtime (CRI), the network plugin's configuration (CNI), and the number of
storage drivers (CSI):

```bash
kubectl get node kbook-worker -o jsonpath='CRI={.status.nodeInfo.containerRuntimeVersion}{"\n"}'
docker exec kbook-worker sh -c 'ls /etc/cni/net.d'
kubectl get csidrivers --no-headers | wc -l
```

```text
CRI=containerd://2.2.0
10-calico.conflist
calico-kubeconfig
0
```

The runtime is `containerd`, the network plugin is Calico, and no CSI driver is
registered. Each answer comes from the cluster or the node, not from this book.

Clean up the demo:

```bash
kubectl delete namespace ch24-demo --wait=true
kubectl delete crd widgets.demo.example.com
```

```text
namespace "ch24-demo" deleted
customresourcedefinition.apiextensions.k8s.io "widgets.demo.example.com" deleted
```

Deleting a CRD deletes every object of its kind, so check first that no one needs them.

### Install an operator and watch it reconcile

Install cert-manager from its chart, with its CRDs, and its leader election in its
own Namespace:

```bash
helm repo add jetstack https://charts.jetstack.io
helm search repo jetstack/cert-manager --version v1.21.2
helm install cert-manager jetstack/cert-manager --version v1.21.2 --namespace ch24-demo-cm --create-namespace --set crds.enabled=true --set global.leaderElection.namespace=ch24-demo-cm --wait --timeout 5m
```

```text
"jetstack" has been added to your repositories
NAME                 	CHART VERSION	APP VERSION	DESCRIPTION
jetstack/cert-manager	v1.21.2      	v1.21.2    	A Helm chart for cert-manager
NAME: cert-manager
LAST DEPLOYED: Fri Oct 23 15:47:52 2026
NAMESPACE: ch24-demo-cm
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
cert-manager v1.21.2 has been deployed successfully!
...
```

Three controllers run, and six CRDs are new. The API now serves the operator's kinds:

```bash
kubectl -n ch24-demo-cm get pods
kubectl api-resources --api-group=cert-manager.io
```

```text
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-cainjector-67758b87f7-8zptj   1/1     Running   0          26s
cert-manager-d9f58588f-g58j2               1/1     Running   0          26s
cert-manager-webhook-68877cb8f5-kgldl      1/1     Running   0          26s
NAME                  SHORTNAMES   APIVERSION           NAMESPACED   KIND
certificaterequests   cr,crs       cert-manager.io/v1   true         CertificateRequest
certificates          cert,certs   cert-manager.io/v1   true         Certificate
clusterissuers        ciss         cert-manager.io/v1   false        ClusterIssuer
issuers               iss          cert-manager.io/v1   true         Issuer
```

Declare what you want: an `Issuer` that signs its own certificates, and a
`Certificate` for one host, kept in the Secret `demo-tls`:

```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: demo
spec:
  secretName: demo-tls
  dnsNames:
    - demo.example.test
  issuerRef:
    kind: Issuer
    name: selfsigned
```

```bash
kubectl create namespace ch24-demo
kubectl -n ch24-demo apply -f cert.yaml
kubectl -n ch24-demo wait --for=condition=Ready certificate/demo --timeout=120s
kubectl -n ch24-demo get issuer,certificate
kubectl -n ch24-demo get secret demo-tls
kubectl -n ch24-demo get secret demo-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -ext subjectAltName -enddate
```

```text
namespace/ch24-demo created
issuer.cert-manager.io/selfsigned created
certificate.cert-manager.io/demo created
certificate.cert-manager.io/demo condition met
NAME                                READY   AGE
issuer.cert-manager.io/selfsigned   True    1s

NAME                               READY   SECRET     AGE
certificate.cert-manager.io/demo   True    demo-tls   1s
NAME       TYPE                DATA   AGE
demo-tls   kubernetes.io/tls   3      1s
subject=
X509v3 Subject Alternative Name: critical
    DNS:demo.example.test
notAfter=Jan 21 13:48:19 2027 GMT
```

Nobody created the Secret by hand: the operator did, and its events show how,
through a private key and a `CertificateRequest`:

```bash
kubectl -n ch24-demo describe certificate demo | sed -n "/^Events:/,\$p"
```

```text
Events:
  Type    Reason     Age   From                                       Message
  ----    ------     ----  ----                                       -------
  Normal  Issuing    1s    cert-manager-certificates-trigger          Issuing certificate as Secret does not exist
  Normal  Generated  1s    cert-manager-certificates-key-manager      Stored new private key in temporary Secret resource "demo-xbw6g"
  Normal  Requested  1s    cert-manager-certificates-request-manager  Created new CertificateRequest resource "demo-1"
  Normal  Issuing    1s    cert-manager-certificates-issuing          The certificate has been successfully issued
```

Now take the actual state away from the desired one, and let the operator put it
back:

```bash
kubectl -n ch24-demo delete secret demo-tls
sleep 5; kubectl -n ch24-demo get secret demo-tls
```

```text
secret "demo-tls" deleted from ch24-demo namespace
NAME       TYPE                DATA   AGE
demo-tls   kubernetes.io/tls   3      5s
```

A new Secret, five seconds old, and a second `CertificateRequest`, `demo-2`, in
the events. That is reconciliation: the desired state is the `Certificate`, and
the Secret is kept in line with it.

The Leases for leader election are in the operator's Namespace, as configured:

```bash
kubectl get leases -n kube-system | grep -c cert-manager
kubectl get leases -n ch24-demo-cm
```

```text
0
NAME                                      HOLDER                                                                          AGE
cert-manager-cainjector-leader-election   cert-manager-cainjector-67758b87f7-8zptj_77c4f9ad-5706-40e5-8eae-e5ddf8489f71   26s
cert-manager-controller                   cert-manager-d9f58588f-g58j2-external-cert-manager-controller                   19s
```

Uninstall it before the lab, which installs its own release. Helm keeps the CRDs:

```bash
helm uninstall cert-manager -n ch24-demo-cm
```

```text
These resources were kept due to the resource policy:
[CustomResourceDefinition] challenges.acme.cert-manager.io
[CustomResourceDefinition] orders.acme.cert-manager.io
[CustomResourceDefinition] certificaterequests.cert-manager.io
[CustomResourceDefinition] certificates.cert-manager.io
[CustomResourceDefinition] clusterissuers.cert-manager.io
[CustomResourceDefinition] issuers.cert-manager.io

release "cert-manager" uninstalled
```

Remove the demo Namespaces with `kubectl delete namespace ch24-demo ch24-demo-cm`.
The lab's setup removes the kept CRDs, so the lab starts without them.

## Hands-on lab

The lab works like a KodeKloud lab: one task at a time, a check after each, and
progress that is saved between sessions.

```bash
make lab CH=24       # set up the lab and show task 1
make check CH=24     # check the current task; if it is right, show the next
make question CH=24  # show the current task again
make reset CH=24     # back to the starting state and task 1
make verify CH=24    # check every task at once
```

Everything happens in the Namespace `ch24-crd`: use `-n ch24-crd` on every command,
or run `make use-namespace CH=24` once. The setup creates the namespace only. The
CRD `backups.ch24.example.com` does not exist at the start, and Task 1 creates it.
Tasks 2 to 4 depend on it. Task 5 is independent. The lab removes the CRD at
reset and teardown, which also removes its objects. Task 6 installs cert-manager
with Helm into the Namespace `ch24-cert-manager`; reset and teardown uninstall it
and remove its CRDs. It needs `helm` (Chapter 14) and access to
`https://charts.jetstack.io`.

Full solutions are in [`lab/solutions.md`](lab/solutions.md).

### Task 1: Create the Backup CRD

Create a CustomResourceDefinition named `backups.ch24.example.com` with the following
specification, and wait until the API serves it.

- Group `ch24.example.com`, kind `Backup`, plural `backups`, singular `backup`
- Scope `Namespaced`, version `v1`, served and stored
- The schema requires `spec.schedule` and `spec.target`, both strings
- The CRD is `Established`

### Task 2: Create a Backup

In namespace `ch24-crd`, create a Backup named `nightly` with the following specification.

- `apiVersion: ch24.example.com/v1`
- `spec.schedule`: `0 2 * * *`
- `spec.target`: `db`

### Task 3: Test the schema

Ask the API server whether it accepts a Backup named `bad-backup` in `ch24-crd` that has
a schedule but no target. Write `rejected` to `/tmp/ch24-validation.txt` if the server
refuses it, or `accepted` if it does not. Do not store the object.

- File `/tmp/ch24-validation.txt` holds `rejected`

### Task 4: List the Backup objects

Write the names of the Backup objects in `ch24-crd`, as `kind/name` (for example
`backup.ch24.example.com/nightly`), to `/tmp/ch24-names.txt`.

- File `/tmp/ch24-names.txt` lists `backup.ch24.example.com/nightly`

### Task 5: Name the container runtime

Write the name of the container runtime on the node `kbook-worker` to `/tmp/ch24-cri.txt`.
Write only the runtime's name, not its version.

- File `/tmp/ch24-cri.txt` holds the runtime name, such as `containerd`

### Task 6: Let an operator issue a certificate

Install cert-manager, then have it issue a self-signed certificate into a Secret.

- Helm release `cert-manager` in a new Namespace `ch24-cert-manager`, from the chart `jetstack/cert-manager` version `v1.21.2` (repository `https://charts.jetstack.io`), with its CRDs
- Its leader election uses the Namespace `ch24-cert-manager`: no cert-manager Leases in `kube-system`
- In `ch24-crd`: an `Issuer` named `selfsigned` that signs its own certificates
- In `ch24-crd`: a `Certificate` named `site` for the DNS name `site.example.test`, issued by `selfsigned` into the Secret `site-tls`
- The Certificate is `Ready`, and the operator created `site-tls` (type `kubernetes.io/tls`) with that name in the certificate

## Exam tips

> **Exam tip:** `kubectl explain KIND.FIELD --api-version=GROUP/VERSION` is the fastest way to write a custom resource correctly. It shows the same schema the server enforces, including the required fields.
>
> **Exam tip:** A custom object is refused with the schema's own message. Read the `invalid:` line, which names the field, before you change the manifest.
>
> **Exam tip:** `kubectl api-resources --api-group=GROUP` lists a group's kinds and their versions. Use it to find the version to write in `apiVersion` when a question names a group but not a version.

## Common mistakes

- Creating a custom object before the CRD is `Established`, and reading the error as a schema problem.
- Writing `apiVersion` with the CRD's name instead of its group and version.
- Expecting a custom object to do something on its own. Without a controller, the object is only stored.
- Deleting a CRD to remove one object. The CRD's deletion removes every object of its kind.
- Confusing the three interfaces: the runtime is CRI, the network plugin is CNI, and the storage driver is CSI.
- Trusting a schema without testing it. A server-side dry run shows whether it accepts an object before anything is stored.
- Changing a CRD's storage version without a conversion plan. Existing objects are read through conversion, and a missing conversion breaks them.
- Creating an operator's Secret or Deployment by hand. Declare the custom resource and let the operator create and keep them.
- Expecting `helm uninstall` to remove an operator's CRDs. Charts keep them on purpose; delete them only when no object of their kinds is needed.

<!-- QUESTIONS:START -->

## End-of-chapter questions

**1.** `KCNA` `CKA` What does a CustomResourceDefinition add to a cluster?

- **A.** A new container runtime
- **B.** A new kind in the Kubernetes API, served and stored like a built-in type
- **C.** A new node in the cluster
- **D.** A replacement for Deployments

**2.** `KCNA` `CKA` Which pairing defines an operator?

- **A.** A DaemonSet and a Service
- **B.** A CRD describing the desired state, and a controller that reconciles the cluster toward it
- **C.** A ConfigMap and a Secret
- **D.** A ServiceAccount and a RoleBinding

**3.** `KCNA` `CKA` Which interface lets the kubelet start and stop containers through a runtime such as containerd?

- **A.** CNI
- **B.** CSI
- **C.** CRI
- **D.** OCI only

**4.** `KCNA` `CKA` Which interface configures a Pod's network and routes, typically with a configuration file in /etc/cni/net.d?

- **A.** CRI
- **B.** CNI
- **C.** CSI
- **D.** RBAC

**5.** `CKA` A CRD serves two versions, and one of them is the storage version. What does that mean?

- **A.** Only that version can be served to clients
- **B.** The API server writes objects to etcd in that version, and converts others to and from it
- **C.** Objects in that version are never validated
- **D.** That version is deleted when the CRD is updated

**6.** `CKA` A custom object does not satisfy the CRD's schema. Where is it refused?

- **A.** In the kubectl client, before the request is sent
- **B.** By the API server, which validates the object against the schema on create and update
- **C.** By the kubelet on the node where the object would run
- **D.** By CoreDNS, when the object's name is resolved

**7.** `KCNA` Which command reads the schema of a custom kind, so you can see its fields and which are required?

- **A.** kubectl get crd
- **B.** kubectl explain KIND.FIELD --api-version=GROUP/VERSION
- **C.** kubectl describe node
- **D.** kubectl top

**8. (Task)** `CKA` Create a CustomResourceDefinition named `caches.perf.example.com`: group `perf.example.com`, kind `Cache`, plural `caches`, singular `cache`, namespaced, one version `v1` that is served and stored. Its schema requires `spec.ttl`, an integer with a minimum of 0. Wait until it is Established, and show its kind.

**9. (Task)** `CKA` In namespace `prod`, create a Cache named `hot` with `spec.ttl` set to `300`, using the CRD `caches.perf.example.com` from the previous question. Show its ttl.

**10. (Task)** `CKA` Write the name of the storage version of the CRD `caches.perf.example.com` into `/tmp/ch24-q10.txt`, and nothing else.

**11. (Task)** `CKA` List the resources that the group `perf.example.com` provides, by their names, with `kubectl api-resources`, and write them to `/tmp/ch24-q11.txt`.

**12.** `CKA` cert-manager is installed, and a Certificate `api` names the Secret `api-tls`. Someone deletes `api-tls`. What happens?

- **A.** Nothing until the Certificate is deleted and created again
- **B.** The operator notices the Secret is missing and issues the certificate again into a new `api-tls`
- **C.** The Certificate is deleted too, by garbage collection
- **D.** The API server refuses the deletion

**13. (Task)** `CKA` cert-manager is running. In namespace `web`, create a self-signed `Issuer` named `local` and a `Certificate` named `portal` for `portal.example.test`, stored in the Secret `portal-tls`. Show that the operator issued it.

<details>
<summary>Answers</summary>

**1. B.** A CRD registers a new kind with the API server, which then serves it at its own path, stores its objects in etcd and validates them against the CRD's schema. It does not change the runtime, add nodes, or replace built-in controllers.

**2. B.** An operator is a CRD, which defines a new kind of desired state, plus a controller that watches those objects and acts to make the cluster match them. A CRD alone only stores data, and it does nothing until a controller acts on it.

**3. C.** The Container Runtime Interface (CRI) is the gRPC interface between the kubelet and the container runtime. CNI gives Pods networks, and CSI handles storage volumes.

**4. B.** The Container Network Interface (CNI) is the plugin interface for Pod networking. Each node reads the plugin's configuration from /etc/cni/net.d. CRI runs containers, CSI handles volumes, and RBAC is an authorization mode.

**5. B.** Exactly one version is the storage version. The API server persists objects in that version, and it converts between the stored form and the other served versions. Each served version has its own schema, and `served` decides which versions clients can use.

**6. B.** The API server enforces the CRD's schema, so the refusal comes back as an error from the server. A client-side check cannot be relied on, which is why `kubectl apply --dry-run=server` is the reliable test.

**7. B.** `kubectl explain` reads the schema the API server serves for a kind, including the required fields. `kubectl get crd` lists the CRDs, and `describe node` and `top` show other information.

**8.**

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: caches.perf.example.com
spec:
  group: perf.example.com
  scope: Namespaced
  names:
    plural: caches
    singular: cache
    kind: Cache
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
              required: [ttl]
              properties:
                ttl:
                  type: integer
                  minimum: 0
YAML
kubectl wait --for=condition=Established crd/caches.perf.example.com --timeout=60s
kubectl get crd caches.perf.example.com -o jsonpath='{.spec.names.kind}{"\n"}'
```

The group and the plural name form the resource's name, `caches.perf.example.com`.
The CRD itself is cluster-scoped, so it has no namespace.

**9.**

```bash
cat <<'YAML' | kubectl -n prod apply -f -
apiVersion: perf.example.com/v1
kind: Cache
metadata:
  name: hot
spec:
  ttl: 300
YAML
kubectl -n prod get cache hot -o jsonpath='{.spec.ttl}{"\n"}'
```

The object's `apiVersion` is the group and version of the CRD, `perf.example.com/v1`.

**10.**

```bash
kubectl get crd caches.perf.example.com -o jsonpath='{.spec.versions[?(@.storage==true)].name}' > /tmp/ch24-q10.txt
cat /tmp/ch24-q10.txt
```

The storage version is the one with `storage: true`. The JSONPath filter selects it,
and the answer is `v1`.

**11.**

```bash
kubectl api-resources --api-group=perf.example.com -o name > /tmp/ch24-q11.txt
cat /tmp/ch24-q11.txt
```

`-o name` prints one resource per line, in the form `caches.perf.example.com`.

**12. B.** The Certificate is the desired state; the Secret is actual state the operator maintains. Reconciliation detects the difference and issues the certificate again. That is the operator pattern: a custom resource, and a controller that keeps the cluster in line with it.

**13.**

```bash
cat <<'YAML' | kubectl -n web apply -f -
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: local
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: portal
spec:
  secretName: portal-tls
  dnsNames:
    - portal.example.test
  issuerRef:
    kind: Issuer
    name: local
YAML
kubectl -n web wait --for=condition=Ready certificate/portal --timeout=120s
kubectl -n web get certificate,secret
kubectl -n web describe certificate portal
```

`kubectl explain certificate.spec` lists the fields, served by the operator's CRD. The Secret appears without anyone creating it, and the Certificate's events name the `CertificateRequest` the operator made.

</details>

<!-- QUESTIONS:END -->

## Further reading

- Kubernetes documentation: *Extend the Kubernetes API with CustomResourceDefinitions*, *Versions in CustomResourceDefinitions*
- Kubernetes documentation: *Operator pattern*, *Container Runtime Interface*, *Network Plugins*, *Container Storage Interface*
- Kubernetes documentation: *API Aggregation* for extending the API with a separate server instead of a CRD
- Chapter 25 next: autoscaling, the HPA, the VPA, and the cluster autoscaler concepts
