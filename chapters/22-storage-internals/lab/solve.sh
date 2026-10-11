#!/usr/bin/env bash
# Automated reference solution (used by CI). Human-readable version: solutions.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

k() { kubectl -n "$LAB_NS" "$@"; }

# Task 1
k apply -f - >/dev/null <<'YAML'
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
k wait --for=condition=Ready pod/writer --timeout=180s >/dev/null
k get pvc app-data -o jsonpath='{.spec.volumeName}' > "$LAB_ANSWER_PV"

# Task 2
pv="$(k get pvc app-data -o jsonpath='{.spec.volumeName}')"
kubectl get pv "$pv" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}' > "$LAB_ANSWER_RECLAIM"

# Task 3
k apply -f - >/dev/null <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared
spec:
  accessModes: [ReadWriteMany]
  storageClassName: ${LAB_SC_IMMEDIATE}
  resources:
    requests:
      storage: 50Mi
YAML
sleep 5
k get pvc shared -o jsonpath='{.status.phase}' > "$LAB_ANSWER_SHARED"

# Task 4
kubectl apply -f - >/dev/null <<YAML
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${LAB_SC_EXPANDABLE}
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
YAML

# Task 5
kubectl get csidrivers --no-headers 2>/dev/null | wc -l | tr -d '[:space:]' > "$LAB_ANSWER_CSI"
