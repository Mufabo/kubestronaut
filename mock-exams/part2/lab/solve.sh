#!/usr/bin/env bash
# Automated reference solution (used by CI). Human-readable version: solutions.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_lab_cluster

C=$COURSE

# Q1
kubectl -n p2-web create configmap site-config --from-literal=THEME=dark --from-literal=LANG=en >/dev/null
kubectl -n p2-web apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: site
spec:
  containers:
    - name: site
      image: nginx:1.27
      envFrom:
        - configMapRef:
            name: site-config
YAML

# Q2
kubectl -n p2-web create secret generic api-key --from-literal=token=s3-p2-token >/dev/null
kubectl -n p2-web apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: worker
spec:
  containers:
    - name: worker
      image: busybox:1.36
      command: ["sleep", "3600"]
      env:
        - name: API_TOKEN
          valueFrom:
            secretKeyRef:
              name: api-key
              key: token
YAML

# Q3
kubectl -n p2-web apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: guarded
spec:
  containers:
    - name: guarded
      image: nginx:1.27
      resources:
        requests:
          cpu: 100m
          memory: 64Mi
        limits:
          cpu: 100m
          memory: 64Mi
      readinessProbe:
        httpGet:
          path: /
          port: 80
YAML

# Q4
kubectl -n p2-batch apply -f - >/dev/null <<'YAML'
apiVersion: batch/v1
kind: Job
metadata:
  name: migrate
spec:
  completions: 3
  parallelism: 1
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: busybox:1.36
          command: ["sh", "-c", "echo migrated"]
YAML

# Q5
kubectl -n p2-batch create cronjob report --image=busybox:1.36 --schedule="0 3 * * *" -- sh -c 'echo report' >/dev/null
kubectl -n p2-batch patch cronjob report -p '{"spec":{"concurrencyPolicy":"Forbid"}}' >/dev/null
kubectl -n p2-batch create job report-now --from=cronjob/report >/dev/null
kubectl -n p2-batch wait --for=condition=Complete job/report-now --timeout=180s >/dev/null

# Q6
kubectl -n p2-data apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: pipeline
spec:
  volumes:
    - name: work
      emptyDir: {}
  initContainers:
    - name: seed
      image: busybox:1.36
      command: ["sh", "-c", "echo 42 > /work/value"]
      volumeMounts:
        - name: work
          mountPath: /work
  containers:
    - name: consume
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: work
          mountPath: /work
YAML

# Q7
kubectl -n p2-data apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: archive
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 200Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: keeper
spec:
  volumes:
    - name: archive
      persistentVolumeClaim:
        claimName: archive
  containers:
    - name: keeper
      image: busybox:1.36
      command: ["sh", "-c", "echo ok > /archive/ok; sleep 3600"]
      volumeMounts:
        - name: archive
          mountPath: /archive
YAML

# Q8
kubectl -n p2-edge patch service shop -p '{"spec":{"selector":{"app":"shop"}}}' >/dev/null

# Q9
kubectl -n p2-edge create ingress shop --class=nginx --rule='shop.p2.example.test/app*=shop:80' >/dev/null

# Q10
helm -n p2-release install web "${C}/10/chart" --set replicaCount=2 >/dev/null

# Q11
kubectl -n p2-release rollout undo deployment/api --to-revision=1 >/dev/null
kubectl -n p2-release rollout status deployment/api --timeout=180s >/dev/null

# Q12
crash_log="$(kubectl -n p2-ops logs crash)"
grep -m1 'fatal' <<<"$crash_log" > "${C}/12/message.txt"

# Q13
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-guard
  namespace: p2-ops
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: api
YAML

# Q14
kubectl -n p2-ops label pod tool-1 tool-2 tool-3 stage=new --overwrite >/dev/null

# Wait for the Pods the questions check, so the score is read from settled objects.
kubectl -n p2-web wait --for=condition=Ready pod/site pod/worker pod/guarded --timeout=180s >/dev/null
kubectl -n p2-data wait --for=condition=Ready pod/keeper --timeout=180s >/dev/null
kubectl -n p2-data wait --for=jsonpath='{.status.phase}'=Running pod/pipeline --timeout=180s >/dev/null
kubectl -n p2-edge rollout status deployment/shop --timeout=180s >/dev/null
