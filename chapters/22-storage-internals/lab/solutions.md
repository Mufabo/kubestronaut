# Chapter 22 lab: solutions

Try each task before reading its solution. The commands below pass
`-n ch22-store` explicitly, because the lab does not change your default namespace.

## Task 1: dynamic provisioning

```bash
cat <<'YAML' | kubectl -n ch22-store apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 50Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: writer
spec:
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: app-data
YAML
kubectl -n ch22-store wait --for=condition=Ready pod/writer --timeout=180s
kubectl -n ch22-store get pvc app-data -o jsonpath='{.spec.volumeName}' > /tmp/ch22-pv.txt
```

The claim has no class, so the default `standard` applies. It binds once the Pod is
scheduled, and the provisioner names the volume `pvc-` followed by an ID.

## Task 2: the reclaim policy of that volume

```bash
pv="$(kubectl -n ch22-store get pvc app-data -o jsonpath='{.spec.volumeName}')"
kubectl get pv "$pv" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}' > /tmp/ch22-reclaim.txt
```

The volume copies the policy of the class that created it, which is `Delete`.

## Task 3: the claim that the backend refuses

```bash
cat <<'YAML' | kubectl -n ch22-store apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared
spec:
  accessModes: [ReadWriteMany]
  storageClassName: ch22-immediate
  resources:
    requests:
      storage: 50Mi
YAML
sleep 5
kubectl -n ch22-store get pvc shared -o jsonpath='{.status.phase}' > /tmp/ch22-shared.txt
kubectl -n ch22-store describe pvc shared | grep ProvisioningFailed
```

The local-path provisioner supports `ReadWriteOnce` and `ReadWriteOncePod` only. The
event names the supported modes, and the claim stays `Pending`.

## Task 4: a class that allows expansion

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ch22-expandable
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
YAML
```

`allowVolumeExpansion` is a field of the class. Setting it to `true` lets a claim from
this class grow. The provisioner must also support expansion for the resize to happen,
and the lab does not test a resize.

## Task 5: count the CSI drivers

```bash
kubectl get csidrivers --no-headers | wc -l | tr -d '[:space:]' > /tmp/ch22-csi.txt
```

The cluster has no CSI driver, so the count is `0`. `kubectl get csinodes` shows the
same, with zero drivers on each node.

## Why these checks accept any correct method

The checks read the claims' phases and volume names, the PV's reclaim policy, the
StorageClass fields, and the CSIDriver count, plus the files you write. You can create the
objects with YAML or with imperative commands, and the checks do not care which.
