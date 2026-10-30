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
require_cmd docker helm

C=$COURSE

# Q1
sed -i 's/^ENV APP_VERSION=.*/ENV APP_VERSION=2.0/' "${C}/1/app/Dockerfile"
docker build -q -t "$CKAD_IMAGE" "${C}/1/app" >/dev/null
docker save -o "${C}/1/ckad-web.tar" "$CKAD_IMAGE"

# Q2
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: logger
  namespace: ckad-design
spec:
  volumes:
    - name: logs
      emptyDir: {}
  initContainers:
    - name: shipper
      image: busybox:1.36
      restartPolicy: Always
      command: ["sh", "-c", "tail -F /var/log/app/app.log"]
      volumeMounts:
        - name: logs
          mountPath: /var/log/app
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "i=0; while true; do i=$((i+1)); echo \"order $i\" >> /var/log/app/app.log; sleep 2; done"]
      volumeMounts:
        - name: logs
          mountPath: /var/log/app
YAML

# Q3
kubectl -n ckad-design apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
spec:
  selector:
    matchLabels:
      app: node-agent
  template:
    metadata:
      labels:
        app: node-agent
    spec:
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      containers:
        - name: agent
          image: busybox:1.36
          command: ["sleep", "3600"]
YAML

# Q4
kubectl -n ckad-design apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: scratch
spec:
  volumes:
    - name: scratch
      emptyDir:
        medium: Memory
        sizeLimit: 64Mi
  containers:
    - name: scratch
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: scratch
          mountPath: /scratch
YAML

# Q5
kubectl -n ckad-deploy patch deployment frontend -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}' >/dev/null
kubectl -n ckad-deploy set image deployment/frontend nginx=nginx:1.27 >/dev/null

# Q6
kubectl -n ckad-deploy apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: checkout
      track: canary
  template:
    metadata:
      labels:
        app: checkout
        track: canary
    spec:
      containers:
        - name: checkout
          image: nginx:1.27
YAML

# Q7
helm -n ckad-deploy upgrade cache "${C}/7/chart" --reuse-values --set image.tag=1.27 --set replicaCount=3 --wait --timeout 180s >/dev/null

# Q8
cat > "${C}/8/overlays/prod/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: ckad-deploy
replicas:
  - name: ledger
    count: 2
labels:
  - pairs:
      env: prod
    includeTemplates: true
EOF
kubectl apply -k "${C}/8/overlays/prod" >/dev/null

# Q9
sed -i 's|^apiVersion: batch/v1beta1$|apiVersion: batch/v1|' "${C}/9/cleanup.yaml"
kubectl apply -f "${C}/9/cleanup.yaml" >/dev/null

# Q10
kubectl -n ckad-ops patch deployment api -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx",
  "readinessProbe":{"httpGet":{"path":"/","port":80},"periodSeconds":5},
  "livenessProbe":{"tcpSocket":{"port":80},"initialDelaySeconds":10,"periodSeconds":20}}]}}}}' >/dev/null

# Q11
worker_log="$(kubectl -n ckad-ops logs batch-runner -c worker)"
grep ERROR <<<"$worker_log" > "${C}/11/errors.txt"

# Q12: give the file the name the command expects, then start fresh Pods.
kubectl -n ckad-ops patch configmap reports-config --type=json \
  -p '[{"op":"move","from":"/data/settings.cfg","path":"/data/settings.conf"}]' >/dev/null
kubectl -n ckad-ops rollout restart deployment/reports >/dev/null

# Q13
kubectl -n ckad-sec create configmap db-config --from-file="${C}/13/db.properties" >/dev/null
kubectl -n ckad-sec create secret generic db-cred --from-literal=username=app --from-literal=password=s3cr3t >/dev/null
kubectl -n ckad-sec apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: db-client
spec:
  volumes:
    - name: config
      configMap:
        name: db-config
    - name: cred
      secret:
        secretName: db-cred
  containers:
    - name: db-client
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: config
          mountPath: /etc/db-config
        - name: cred
          mountPath: /etc/db-cred
          readOnly: true
YAML

# Q14
kubectl -n ckad-sec apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: hardened
spec:
  securityContext:
    runAsUser: 1000
    runAsGroup: 3000
    runAsNonRoot: true
  containers:
    - name: hardened
      image: busybox:1.36
      command: ["sleep", "3600"]
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
YAML

# Q15
kubectl -n ckad-sec create serviceaccount deployer >/dev/null
kubectl -n ckad-sec create role deploy-editor --verb=get,list,create,update,patch --resource=deployments.apps >/dev/null
kubectl -n ckad-sec create rolebinding deployer-binding --role=deploy-editor --serviceaccount=ckad-sec:deployer >/dev/null
kubectl -n ckad-sec create deployment ci --image=nginx:1.27 >/dev/null
kubectl -n ckad-sec set serviceaccount deployment ci deployer >/dev/null

# Q16
kubectl -n ckad-quota set resources deployment burst --requests=cpu=100m,memory=64Mi --limits=cpu=200m,memory=128Mi >/dev/null

# Q17
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: ckad.kbook.io/v1
kind: Cache
metadata:
  name: session-cache
  namespace: ckad-sec
spec:
  size: medium
  replicas: 3
YAML

# Q18
kubectl -n ckad-net patch service catalog --type=json -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":"http"}]' >/dev/null

# Q19
kubectl -n ckad-net apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-access
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api
      ports:
        - protocol: TCP
          port: 80
YAML

# Q20
kubectl -n ckad-net expose deployment cart --port=8080 --target-port=80 >/dev/null
kubectl -n ckad-net create ingress store --class=nginx \
  --rule='store.ckad.example.test/shop*=shop:80' --rule='store.ckad.example.test/cart*=cart:8080' >/dev/null

# Wait for everything the checks read, so the score comes from settled objects.
kubectl -n ckad-design wait --for=condition=Ready pod/logger pod/scratch --timeout=180s >/dev/null
kubectl -n ckad-design rollout status daemonset/node-agent --timeout=180s >/dev/null
for d in frontend checkout-canary ledger; do kubectl -n ckad-deploy rollout status "deployment/${d}" --timeout=180s >/dev/null; done
for d in api reports; do kubectl -n ckad-ops rollout status "deployment/${d}" --timeout=180s >/dev/null; done
kubectl -n ckad-sec rollout status deployment/ci --timeout=180s >/dev/null
kubectl -n ckad-sec wait --for=condition=Ready pod/db-client pod/hardened --timeout=180s >/dev/null
kubectl -n ckad-quota rollout status deployment/burst --timeout=180s >/dev/null
reports_settled() { [[ "$(kubectl -n ckad-ops get deployment reports -o jsonpath='{.status.replicas}')" == 1 ]]; }
wait_for "the old reports Pod to go" 180 reports_settled
web_blocked() { ! kubectl -n ckad-net exec web -- wget -qO- -T 2 http://db >/dev/null 2>&1; }
wait_for "the NetworkPolicy to block web" 120 web_blocked
logger_ships() { local l; l="$(kubectl -n ckad-design logs logger -c shipper --tail=1 2>/dev/null)"; grep -q '^order' <<<"$l"; }
wait_for "the sidecar to print the log" 60 logger_ships
