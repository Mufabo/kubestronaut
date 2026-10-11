# Chapter 22: Storage internals: CSI, dynamic provisioning, access modes, and volume expansion

> **Exams:** CKA
> **Difficulty:** Advanced
> **Time:** ~55 min reading, ~35 min lab
> **Lab tier:** 1 (kind)
> **Prerequisites:** Chapter 13 (PersistentVolumes, claims and StorageClasses)

## Learning objectives

After this chapter you can:

- Explain how the Container Storage Interface (CSI) lets a storage vendor's driver plug into Kubernetes, and what objects a CSI driver leaves in the cluster
- Trace a dynamically provisioned volume from a claim, through the StorageClass's provisioner, to a bound PersistentVolume
- Choose an access mode that a storage backend can actually provide, and recognize a claim that a backend refuses
- Predict a volume's reclaim policy from the StorageClass that created it
- Enable volume expansion correctly, and explain why a claim cannot grow unless its class allows it and its driver supports it
- Explain why a claim with `volumeBindingMode: WaitForFirstConsumer` stays `Pending` until a Pod uses it

## Concepts

### Why storage needed an interface

Kubernetes does not know how to create a disk. A cloud provider's block volumes,
an NFS export, a Ceph pool, and a node's local directory all work differently.
For a long time these were built into Kubernetes itself, and each new backend
meant a change to the core code. The **Container Storage Interface (CSI)** is the
standard that moved storage out of that core. A storage vendor ships a **CSI
driver**: a set of components that run in the cluster and answer requests from
Kubernetes to create, attach, mount, and delete volumes.

The driver's pieces come in two groups:

- A **controller** part, usually a Deployment, that creates and deletes volumes
  and attaches them to nodes. It talks to the storage backend's API.
- A **node** part, a DaemonSet, that mounts an attached volume into a Pod on its
  node. It also runs on every node that may host a Pod using the driver.

```mermaid
flowchart LR
  C[PVC] -->|StorageClass provisioner| P[CSI controller: CreateVolume]
  P --> PV[PersistentVolume]
  PV -->|attach| A[VolumeAttachment]
  A --> N[CSI node: mount into the Pod]
```

The claim names a StorageClass. The class's provisioner is the CSI driver's name.
The controller creates the volume, Kubernetes records a PersistentVolume, the
volume is attached to the node where the Pod runs, and the node driver mounts it.

### What a CSI driver leaves in the cluster

A driver registers itself with two kinds of object you can list:

- A **CSIDriver** object, one per driver, that describes what the driver supports:
  whether it can attach volumes, whether it needs the pod's service account
  token, and whether it supports volume expansion.
- A **CSINode** object per node, that lists the drivers running on that node and
  how many volumes each can attach.

A cluster with no CSI driver has none of these. The lab cluster of this book uses
the **local-path provisioner**, which is an external provisioner, not a CSI
driver, so `kubectl get csidrivers` returns nothing. Dynamic provisioning still
works for it, because the StorageClass names the provisioner. The concepts are
the same; only the mechanics differ.

### Dynamic provisioning, end to end

With dynamic provisioning, nobody creates a PersistentVolume by hand. The sequence is:

1. A user creates a PersistentVolumeClaim that names a StorageClass (or uses the default).
2. The class's provisioner sees the claim and creates a volume. For CSI, that is
   the controller's `CreateVolume` call. The volume's name starts with `pvc-` and
   a hash, so you can recognize one.
3. Kubernetes creates a PersistentVolume for the new volume and binds it to the claim.
4. The Pod that uses the claim is scheduled, the volume is attached and mounted, and the Pod runs.

Under `WaitForFirstConsumer`, step 2 waits until a Pod is scheduled, so the volume
is created where the Pod runs. Under `Immediate`, step 2 happens as soon as the
claim exists.

### Access modes and what a backend supports

The access mode is a request, and the backend decides whether it can be honoured.

- `ReadWriteOnce` (RWO) is mounted read-write by a single node.
- `ReadWriteOncePod` (RWOP) is mounted read-write by a single Pod across the cluster.
- `ReadOnlyMany` (ROX) and `ReadWriteMany` (RWX) need a backend that can share a
  volume between nodes, such as NFS or a clustered file system.

A claim asking for a mode its backend cannot provide does not bind. The
provisioner records the reason in an event, and the claim stays `Pending`. The
lab's local-path provisioner refuses everything except RWO and RWOP:

```text
Warning  ProvisioningFailed  failed to provision volume with StorageClass "ch22-immediate": NodePath only supports ReadWriteOnce and ReadWriteOncePod (1.22+) access modes
```

Read the event before you change the claim. The access mode and the backend have
to agree, and the StorageClass is the place that says which backend a claim gets.

### Reclaim policy

A dynamically provisioned volume copies its reclaim policy from the StorageClass
that created it. The usual values:

- `Delete` removes the volume and its data when the claim is deleted. Most
  classes use this, including the default class of the lab cluster.
- `Retain` keeps the volume after its claim is deleted, and the volume moves to
  `Released`. Chapter 13 covered this.

To see the policy of a volume, read the PV, not the class, because a class's
policy applies only to volumes created after the class changed.

### Volume expansion

A claim can ask for more storage later by raising its `resources.requests.storage`.
That only works when two things are true:

- The StorageClass has `allowVolumeExpansion: true`. The default is false.
- The driver supports expansion. The CSIDriver object says so for CSI drivers.

When both hold, the controller grows the volume, and the node resizes the
filesystem, sometimes only when the Pod restarts. A claim that asks for more space
when either condition fails stays at its old size, and its status shows a
resize condition that explains why.

Expansion is one-way: a volume cannot shrink.

## Guided walkthrough

The walkthrough works in the Namespace `ch22-store`. The outputs below are
trimmed: names, ages, and the generated volume names differ on your cluster. The
objects are named `demo-...` so they do not clash with the lab. The lab later in
this chapter uses that Namespace too, so run `make lab CH=22` first, or run the
commands in any Namespace you choose.

### Check for CSI drivers

Ask the cluster which CSI drivers and nodes it has:

```bash
kubectl get csidrivers
kubectl get csinodes
```

```text
No resources found
NAME                  DRIVERS   AGE
kbook-control-plane   0         121m
kbook-worker          0         121m
kbook-worker2         0         121m
```

No CSI driver is registered, and every node reports zero. The default storage
class still works, because its provisioner is the local-path provisioner, an
external provisioner rather than a CSI driver. On a cluster with a cloud or
storage vendor's CSI driver, these lists show the driver's name and each node's
attach limit.

### Read the default StorageClass

```bash
kubectl get storageclass standard -o custom-columns=NAME:.metadata.name,PROVISIONER:.provisioner,RECLAIM:.reclaimPolicy,BINDING:.volumeBindingMode,EXPAND:.allowVolumeExpansion
```

```text
NAME       PROVISIONER             RECLAIM   BINDING                EXPAND
standard   rancher.io/local-path   Delete    WaitForFirstConsumer   <none>
```

The provisioner names the driver, the reclaim policy is `Delete`, the binding is
`WaitForFirstConsumer`, and expansion is not allowed (`<none>` means the default,
false).

### Provision a volume dynamically

Create a claim with no class, so the default applies, and a Pod that mounts it:

```bash
kubectl -n ch22-store create -f - <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-claim
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 100Mi
YAML
kubectl -n ch22-store get pvc demo-claim
```

```text
NAME         STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
demo-claim   Pending                                      standard       <unset>                 0s
```

The claim is `Pending`, because the class waits for a consumer. Mount it in a
Pod, and look again:

```bash
kubectl -n ch22-store run demo-writer --image=busybox:1.36 --restart=Never --overrides='{"spec":{"volumes":[{"name":"d","persistentVolumeClaim":{"claimName":"demo-claim"}}],"containers":[{"name":"app","image":"busybox:1.36","command":["sleep","3600"],"volumeMounts":[{"name":"d","mountPath":"/data"}]}]}}'
kubectl -n ch22-store wait --for=condition=Ready pod/demo-writer --timeout=120s
kubectl -n ch22-store get pvc demo-claim
PV=$(kubectl -n ch22-store get pvc demo-claim -o jsonpath='{.spec.volumeName}')
kubectl get pv "$PV" -o custom-columns=NAME:.metadata.name,CAPACITY:.spec.capacity.storage,RECLAIM:.spec.persistentVolumeReclaimPolicy,STATUS:.status.phase,CLAIM:.spec.claimRef.name,SC:.spec.storageClassName
```

```text
pod/demo-writer created
NAME         STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
demo-claim   Bound    pvc-275c6f88-e29b-4b3f-ae48-6a20be253398   100Mi      RWO            standard       <unset>                 7s
NAME                                       CAPACITY   RECLAIM   STATUS   CLAIM        SC
pvc-275c6f88-e29b-4b3f-ae48-6a20be253398   100Mi      Delete    Bound    demo-claim   standard
```

The provisioner created the PV, named `pvc-` followed by an ID, and bound it. Its
reclaim policy came from the class.

### Ask for an access mode the backend refuses

Create a claim for `ReadWriteMany` from a class that binds at once. The lab's
setup created that class, `ch22-immediate`:

```bash
kubectl -n ch22-store create -f - <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-shared
spec:
  accessModes: [ReadWriteMany]
  storageClassName: ch22-immediate
  resources:
    requests:
      storage: 50Mi
YAML
sleep 6
kubectl -n ch22-store get pvc demo-shared
kubectl -n ch22-store get events --field-selector involvedObject.name=demo-shared -o jsonpath='{range .items[?(@.reason=="ProvisioningFailed")]}{.message}{"\n"}{end}' | head -1
```

```text
NAME          STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS     VOLUMEATTRIBUTESCLASS   AGE
demo-shared   Pending                                      ch22-immediate   <unset>                 6s
failed to provision volume with StorageClass "ch22-immediate": NodePath only supports ReadWriteOnce and ReadWriteOncePod (1.22+) access modes
```

The claim stays `Pending`, and the event gives the reason: this provisioner
supports only the single-node modes. A backend that supports sharing, such as NFS,
would bind the same claim.

Clean up the demo objects:

```bash
kubectl -n ch22-store delete pod demo-writer --wait=true
kubectl -n ch22-store delete pvc demo-claim demo-shared --wait=true
```

```text
pod "demo-writer" deleted
persistentvolumeclaim "demo-claim" deleted
persistentvolumeclaim "demo-shared" deleted
```

Deleting `demo-claim` removes its PV too, because the policy is `Delete`.

## Hands-on lab

The lab works like a KodeKloud lab: one task at a time, a check after each, and
progress that is saved between sessions.

```bash
make lab CH=22       # set up the lab and show task 1
make check CH=22     # check the current task; if it is right, show the next
make question CH=22  # show the current task again
make reset CH=22     # back to the starting state and task 1
make verify CH=22    # check every task at once
```

Everything happens in the Namespace `ch22-store`: use `-n ch22-store` on every
command, or run `make use-namespace CH=22` once. The setup creates one StorageClass,
`ch22-immediate`, which binds at once. The answers go to four files under `/tmp`,
which teardown removes. Task 4 creates a StorageClass, and teardown removes it too.

Full solutions are in [`lab/solutions.md`](lab/solutions.md).

### Task 1: Dynamic provisioning

Create a PersistentVolumeClaim named `app-data`, requesting `50Mi` with access mode
`ReadWriteOnce`, using the default storage class. Create a Pod named `writer` that
runs `busybox:1.36` with the command `sleep 3600` and mounts the claim at `/data`.
Write the name of the PersistentVolume bound to `app-data` into `/tmp/ch22-pv.txt`.

- Claim `app-data` is `Bound`, to a volume the provisioner created (its name starts with `pvc-`)
- Pod `writer` is `Running`
- File `/tmp/ch22-pv.txt` holds that volume's name

### Task 2: The reclaim policy of that volume

Write the reclaim policy of the PersistentVolume bound to `app-data` into
`/tmp/ch22-reclaim.txt`. It is the policy the default storage class gives its volumes.

- File `/tmp/ch22-reclaim.txt` holds the volume's reclaim policy

### Task 3: An access mode the backend refuses

Create a PersistentVolumeClaim named `shared`, requesting `50Mi` with access mode
`ReadWriteMany`, using the storage class `ch22-immediate`. Wait a few seconds, then
write the claim's phase into `/tmp/ch22-shared.txt`.

- Claim `shared` requests `ReadWriteMany` and is `Pending`
- File `/tmp/ch22-shared.txt` holds `Pending`

### Task 4: A StorageClass that allows expansion

Create a StorageClass named `ch22-expandable` with the provisioner
`rancher.io/local-path`, reclaim policy `Delete`, volume binding mode
`WaitForFirstConsumer`, and `allowVolumeExpansion: true`.

- StorageClass `ch22-expandable`: expansion allowed, `WaitForFirstConsumer`, provisioner `rancher.io/local-path`

### Task 5: Count the CSI drivers

Write the number of CSIDriver objects in the cluster into `/tmp/ch22-csi.txt`.

- File `/tmp/ch22-csi.txt` holds the count of CSIDriver objects

## Exam tips

> **Exam tip:** A claim that stays `Pending` is explained by its events. `kubectl describe pvc NAME` shows a `ProvisioningFailed` warning when the access mode or class is wrong, and nothing when the claim is only waiting for a Pod.
>
> **Exam tip:** To grow a claim, edit `spec.resources.requests.storage` and check first that its StorageClass has `allowVolumeExpansion: true`. A claim cannot shrink.
>
> **Exam tip:** The reclaim policy belongs to the PV, and a class sets it only for the volumes it creates. Read it from the PV when a question asks what happens after a claim is deleted.

## Common mistakes

- Requesting `ReadWriteMany` from a class whose backend supports only `ReadWriteOnce`, then waiting for the claim to bind.
- Expecting a claim to grow when its class does not set `allowVolumeExpansion: true`.
- Reading the StorageClass's reclaim policy as the policy of an existing volume. Changing the class does not change volumes that already exist.
- Assuming a `WaitForFirstConsumer` claim is broken when it is `Pending` without a Pod.
- Believing the lab cluster has a CSI driver. It has none; its volumes come from an external provisioner.
- Expecting a volume to shrink. Expansion is one-way.

<!-- QUESTIONS:START -->

## End-of-chapter questions

**1.** `CKA` What problem does the Container Storage Interface (CSI) solve for Kubernetes?

- **A.** It replaces PersistentVolumes with a faster storage object
- **B.** It lets storage vendors ship drivers that plug into Kubernetes without changes to Kubernetes itself
- **C.** It encrypts every volume automatically
- **D.** It makes every access mode available on every backend

**2.** `CKA` Which part of a CSI driver creates and deletes volumes and attaches them to nodes?

- **A.** The node part, a DaemonSet
- **B.** The controller part, usually a Deployment
- **C.** The kubelet, through its CRI
- **D.** CoreDNS, which resolves the volume name

**3.** `CKA` Which object registers a CSI driver with the cluster, describing whether it supports expansion and attachment?

- **A.** A StorageClass
- **B.** A CSIDriver object
- **C.** A CSINode object
- **D.** A VolumeSnapshot

**4.** `CKA` A claim uses a StorageClass with `volumeBindingMode: WaitForFirstConsumer`, and it is Pending. No Pod uses it. What is the cause?

- **A.** The provisioner is broken
- **B.** The claim is waiting for a Pod, so the volume is created on the node where that Pod runs
- **C.** The access mode is not supported
- **D.** The claim requested too much storage

**5.** `CKA` A claim asks for `ReadWriteMany`, and its backend supports only `ReadWriteOnce`. What do you see?

- **A.** The claim binds, and the access mode is quietly downgraded
- **B.** The claim stays Pending, and the events show a ProvisioningFailed warning that names the supported access modes
- **C.** The API server rejects the claim when it is created
- **D.** The claim binds to any available volume, whatever its access mode

**6.** `CKA` Which conditions must hold before a bound claim can grow from 1Gi to 2Gi?

- **A.** The StorageClass has `allowVolumeExpansion: true`, and the driver supports expansion
- **B.** The claim must be deleted and recreated with the larger size
- **C.** The volume's reclaim policy must be Retain
- **D.** Only the node must be restarted

**7.** `CKA` A claim with no explicit reclaim setting is served by a StorageClass whose `reclaimPolicy` is `Retain`. What reclaim policy does the PV it creates have?

- **A.** Delete, the default for every volume
- **B.** Retain, copied from the StorageClass that created it
- **C.** Recycle, because Retain is an alias for it
- **D.** Whatever the claim's annotations say

**8. (Task)** `CKA` Create a StorageClass named `ssd-retain` with the provisioner `rancher.io/local-path`, reclaim policy `Retain`, volume binding mode `WaitForFirstConsumer`, and expansion allowed. Show its reclaim policy and whether expansion is allowed.

**9. (Task)** `CKA` In namespace `prod`, create a PersistentVolumeClaim named `logs` requesting `1Gi` with access mode `ReadWriteOnce` and the default storage class, and a Pod `logger` (busybox:1.36, command `sleep 3600`) that mounts it at `/var/log/app`. Once the claim is Bound, write the name of its PersistentVolume into `/tmp/ch22-q09-pv.txt`.

**10. (Task)** `CKA` In namespace `prod`, the claim `media` requests `ReadWriteMany` from the default storage class, and it is stuck in `Pending`. Change it so that it binds, keeping `2Gi`. Use a Pod `player` (busybox:1.36, command `sleep 3600`) that mounts it at `/media`. Show the claim's phase.

**11. (Task)** `CKA` Write the value of `allowVolumeExpansion` for the default StorageClass into `/tmp/ch22-q11.txt`. The value is `true` or `false`, and nothing else.

<details>
<summary>Answers</summary>

**1. B.** Before CSI, storage backends were built into Kubernetes. CSI is a standard interface, so a vendor ships its own driver, and Kubernetes calls the driver to create, attach, mount and delete volumes. CSI does not change access mode support or add encryption; those depend on the driver.

**2. B.** The controller part handles CreateVolume, DeleteVolume and attach requests, usually as a Deployment. The node part, a DaemonSet, mounts an attached volume into a Pod on its node.

**3. B.** A CSIDriver object describes one driver and what it supports. A CSINode object lists the drivers on one node. A StorageClass names a provisioner, and a VolumeSnapshot is a point-in-time copy of a volume.

**4. B.** `WaitForFirstConsumer` delays volume creation until a Pod that uses the claim is scheduled, so the volume can be placed on that Pod's node. The claim is working as designed. With `Immediate`, the volume is created as soon as the claim exists.

**5. B.** The API server accepts the claim, because it is a valid object. The provisioner refuses to create a volume for an access mode the backend cannot provide, and the claim stays Pending. The event message says which modes the backend supports.

**6. A.** Growing a claim needs the class to allow it (`allowVolumeExpansion: true`), and the driver to support it. Deleting the claim would delete the data under the default policy. Expansion is one-way, so a volume cannot shrink.

**7. B.** A dynamically provisioned volume copies its reclaim policy from the StorageClass that created it. Changing the class later does not change volumes that already exist, so read the policy from the PV.

**8.**

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ssd-retain
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
YAML
kubectl get storageclass ssd-retain -o jsonpath='{.reclaimPolicy} {.allowVolumeExpansion}{"\n"}'
```

StorageClasses are cluster-scoped, so there is no namespace. Expansion is a field of the
class, and it must be `true` for any claim from this class to grow.

**9.**

```bash
cat <<'YAML' | kubectl -n prod apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: logs
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: logger
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: logs
          mountPath: /var/log/app
  volumes:
    - name: logs
      persistentVolumeClaim:
        claimName: logs
YAML
kubectl -n prod wait --for=jsonpath='{.status.phase}'=Bound pvc/logs --timeout=120s
kubectl -n prod get pvc logs -o jsonpath='{.spec.volumeName}{"\n"}' > /tmp/ch22-q09-pv.txt
```

The claim binds once the Pod is scheduled, because the default class waits for a consumer.

**10.**

```bash
kubectl -n prod delete pvc media --wait=true
cat <<'YAML' | kubectl -n prod apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: media
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 2Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: player
spec:
  containers:
    - name: player
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: media
          mountPath: /media
  volumes:
    - name: media
      persistentVolumeClaim:
        claimName: media
YAML
kubectl -n prod wait --for=jsonpath='{.status.phase}'=Bound pvc/media --timeout=120s
kubectl -n prod get pvc media -o jsonpath='{.status.phase}{"\n"}'
```

The access mode of a claim cannot be changed in place, so the claim is recreated.
The default backend supports only `ReadWriteOnce`, so that mode binds.

**11.**

```bash
kubectl get storageclass -o go-template='{{range .items}}{{if eq (index .metadata.annotations "storageclass.kubernetes.io/is-default-class") "true"}}{{if .allowVolumeExpansion}}true{{else}}false{{end}}{{end}}{{end}}{{"\n"}}' > /tmp/ch22-q11.txt
cat /tmp/ch22-q11.txt
```

The default class is the one annotated `storageclass.kubernetes.io/is-default-class: "true"`.
In this cluster the field is not set, so the answer is `false`.

</details>

<!-- QUESTIONS:END -->

## Further reading

- Kubernetes documentation: *Container Storage Interface (CSI)*, *CSI Volumes*, *CSIDriver*, *CSINode*
- Kubernetes documentation: *Dynamic Volume Provisioning*, *Expanding Persistent Volumes Claims*
- Kubernetes documentation: *Storage Classes*, *Volume Attributes Classes*
- Chapter 23 next: RBAC and ServiceAccounts, who may use the objects in this chapter
