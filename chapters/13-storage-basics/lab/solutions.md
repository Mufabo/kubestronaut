# Chapter 13 lab: solutions

Try each task before reading its solution. The commands below assume `kubectl`
defaults to `ch13-storage` (run `make use-namespace CH=13` once). Otherwise, add
`-n ch13-storage` to every command.

## Task 1: `data-claim` and `writer`

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-claim
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 100Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: writer
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: data-claim
YAML
kubectl wait --for=condition=Ready pod/writer --timeout=120s
kubectl exec writer -- sh -c 'echo stored > /data/hello.txt'
```

The claim has no `storageClassName`, so the default class applies. It stays
`Pending` until the Pod is scheduled, then becomes `Bound`.

## Task 2: move the claim to `reader`

```bash
kubectl delete pod writer --wait=true
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: reader
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: data-claim
YAML
kubectl wait --for=condition=Ready pod/reader --timeout=120s
kubectl exec reader -- cat /data/hello.txt
```

The claim outlives the Pod, so `reader` sees the same file.

## Task 3: `ch13-manual-pv` and `manual-claim`

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ch13-manual-pv
spec:
  capacity:
    storage: 1Gi
  accessModes: [ReadWriteOnce]
  storageClassName: manual
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/ch13-data
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: manual-claim
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: manual
  resources:
    requests:
      storage: 500Mi
YAML
kubectl get pvc manual-claim -o jsonpath='{.spec.volumeName}{"\n"}'
```

The claim binds at once: same class, enough capacity, compatible access mode.
Its `volumeName` is `ch13-manual-pv`.

## Task 4: `scratch`, an emptyDir with a size limit

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: scratch
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: cache
          mountPath: /cache
  volumes:
    - name: cache
      emptyDir:
        sizeLimit: 10Mi
YAML
```

The `sizeLimit` is a field of the volume, under `volumes`.

## Task 5: `ch13-retain`, `retained` and `retained-user`

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ch13-retain
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: retained
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ch13-retain
  resources:
    requests:
      storage: 50Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: retained-user
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: retained
YAML
kubectl wait --for=condition=Ready pod/retained-user --timeout=120s
```

The claim stays `Pending` until `retained-user` is scheduled, because the class
uses `WaitForFirstConsumer`. The volume it creates has the reclaim policy `Retain`.

## Why these checks accept any correct method

Each check reads the objects the API server stores: the claims' phases and
volume names, the PV's fields, the Pods' volumes and mounts, the StorageClass,
and the file contents a running container reports. Task 1's check accepts
whichever Pod mounts the claim at the time, so it still passes after Task 2.
