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
printf 'USER 1000\nEXPOSE 8080\n' >> "${C}/1/app/Dockerfile"
docker build -q -t "$CKAD_IMAGE" "${C}/1/app" >/dev/null
docker save -o "${C}/1/ckad2-api.tar" "$CKAD_IMAGE"

# Q2, Q3, Q4
kubectl -n ckad2-design apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: web-cache
spec:
  volumes:
    - name: html
      emptyDir: {}
  initContainers:
    - name: fetch
      image: busybox:1.36
      command: ["sh", "-c", "echo 'ckad2 ready' > /html/index.html"]
      volumeMounts:
        - name: html
          mountPath: /html
  containers:
    - name: web
      image: nginx:1.27
      volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cleanup
spec:
  schedule: "*/15 * * * *"
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 1
  startingDeadlineSeconds: 60
  jobTemplate:
    spec:
      activeDeadlineSeconds: 30
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: cleanup
              image: busybox:1.36
              command: ["sh", "-c", "echo cleaning"]
---
apiVersion: v1
kind: Service
metadata:
  name: kv
spec:
  clusterIP: None
  selector:
    app: kv
  ports:
    - port: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kv
spec:
  serviceName: kv
  replicas: 2
  selector:
    matchLabels:
      app: kv
  template:
    metadata:
      labels:
        app: kv
    spec:
      containers:
        - name: kv
          image: nginx:1.27
          volumeMounts:
            - name: data
              mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 64Mi
YAML

# Q5
kubectl -n ckad2-deploy patch deployment reports --type=json \
  -p='[{"op":"replace","path":"/spec/strategy","value":{"type":"Recreate"}}]' >/dev/null
kubectl -n ckad2-deploy set image deployment/reports nginx=nginx:1.27 >/dev/null

# Q6
kubectl -n ckad2-deploy patch service shop -p '{"spec":{"selector":{"app":"shop","version":"green"}}}' >/dev/null
kubectl -n ckad2-deploy scale deployment shop-blue --replicas=0 >/dev/null

# Q7
helm -n ckad2-deploy rollback catalog 1 --wait --timeout 180s >/dev/null

# Q8
cat > "${C}/8/overlays/staging/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: ckad2-deploy
namePrefix: staging-
images:
  - name: nginx
    newTag: "1.27"
configMapGenerator:
  - name: app-config
    behavior: merge
    literals:
      - MODE=staging
EOF
kubectl apply -k "${C}/8/overlays/staging" >/dev/null

# Q9
sed -i 's|^apiVersion: autoscaling/v2beta2$|apiVersion: autoscaling/v2|' "${C}/9/hpa.yaml"
kubectl apply -f "${C}/9/hpa.yaml" >/dev/null

# Q10
kubectl -n ckad2-ops patch deployment slow -p '{"spec":{"template":{"spec":{"containers":[{"name":"slow",
  "startupProbe":{"exec":{"command":["cat","/tmp/ready"]},"periodSeconds":5,"failureThreshold":12}}]}}}}' >/dev/null

# Q11
burner_measured() {
  local out
  out="$(kubectl -n ckad2-ops top pod -l app=load --no-headers 2>/dev/null)"
  [[ "$(grep -c . <<<"$out")" == 3 ]]
}
wait_for "metrics for the app=load Pods" 300 burner_measured
kubectl -n ckad2-ops top pod -l app=load --sort-by=cpu --no-headers | awk 'NR==1 {print $1}' > "${C}/11/pod.txt"

# Q12
kubectl -n ckad2-ops patch configmap client-config -p '{"data":{"API_URL":"http://api"}}' >/dev/null

# Q13 to Q17
kubectl -n ckad2-sec create serviceaccount reporter >/dev/null
kubectl -n ckad2-sec patch serviceaccount reporter -p '{"automountServiceAccountToken":false}' >/dev/null
kubectl -n ckad2-sec create serviceaccount viewer >/dev/null
kubectl -n ckad2-sec create role pod-viewer --verb=get,list --resource=pods,pods/log >/dev/null
kubectl -n ckad2-sec create rolebinding viewer-binding --role=pod-viewer --serviceaccount=ckad2-sec:viewer >/dev/null
kubectl -n ckad2-sec create secret tls web-tls --cert="${C}/15/tls.crt" --key="${C}/15/tls.key" >/dev/null
kubectl -n ckad2-sec apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: reporter
spec:
  serviceAccountName: reporter
  volumes:
    - name: report-token
      projected:
        sources:
          - serviceAccountToken:
              audience: reports
              expirationSeconds: 3600
              path: token
  containers:
    - name: reporter
      image: busybox:1.36
      command: ["sleep", "infinity"]
      volumeMounts:
        - name: report-token
          mountPath: /var/run/reports
---
apiVersion: v1
kind: Pod
metadata:
  name: web-tls
spec:
  volumes:
    - name: tls
      secret:
        secretName: web-tls
  containers:
    - name: web
      image: busybox:1.36
      command: ["sleep", "infinity"]
      volumeMounts:
        - name: tls
          mountPath: /etc/tls
          readOnly: true
---
apiVersion: v1
kind: Pod
metadata:
  name: netadmin
spec:
  volumes:
    - name: tmp
      emptyDir: {}
  containers:
    - name: netadmin
      image: busybox:1.36
      command: ["sleep", "infinity"]
      securityContext:
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
          add: ["NET_ADMIN"]
      volumeMounts:
        - name: tmp
          mountPath: /tmp
YAML

# Q16: the LimitRange first, so that the Pod gets its defaults.
kubectl -n ckad2-quota apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: LimitRange
metadata:
  name: defaults
spec:
  limits:
    - type: Container
      default:
        cpu: 200m
        memory: 128Mi
      defaultRequest:
        cpu: 100m
        memory: 64Mi
YAML
kubectl -n ckad2-quota run plain --image=busybox:1.36 -- sleep infinity >/dev/null

# Q18: DNS, and the backend Pods on their own port, 80.
kubectl -n ckad2-net apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-egress
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:
        - podSelector:
            matchLabels:
              app: backend
      ports:
        - protocol: TCP
          port: 80
YAML

# Q19, Q20
kubectl -n ckad2-net apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Service
metadata:
  name: legacy-np
spec:
  type: NodePort
  selector:
    app: legacy
  ports:
    - port: 80
      targetPort: 80
      nodePort: ${NODE_PORT}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: portal
spec:
  ingressClassName: nginx
  defaultBackend:
    service:
      name: fallback
      port:
        number: 80
  tls:
    - hosts: [portal.ckad2.example.test]
      secretName: portal-tls
  rules:
    - host: portal.ckad2.example.test
      http:
        paths:
          - path: /api
            pathType: Exact
            backend:
              service:
                name: api
                port:
                  number: 80
YAML

# Wait for everything the checks read, so the score comes from settled objects.
kubectl -n ckad2-design wait --for=condition=Ready pod/web-cache --timeout=180s >/dev/null
kubectl -n ckad2-design rollout status statefulset/kv --timeout=300s >/dev/null
kubectl -n ckad2-deploy rollout status deployment/reports --timeout=180s >/dev/null
kubectl -n ckad2-deploy rollout status deployment/staging-web --timeout=180s >/dev/null
kubectl -n ckad2-deploy rollout status deployment/catalog --timeout=180s >/dev/null
kubectl -n ckad2-ops rollout status deployment/slow --timeout=300s >/dev/null
kubectl -n ckad2-ops wait --for=condition=Ready pod/api-client --timeout=180s >/dev/null
kubectl -n ckad2-sec wait --for=condition=Ready pod/reporter pod/web-tls pod/netadmin --timeout=180s >/dev/null
kubectl -n ckad2-quota wait --for=condition=Ready pod/plain --timeout=180s >/dev/null
old_slow_gone() { [[ "$(kubectl -n ckad2-ops get pods -l app=slow -o name | grep -c .)" == 1 ]]; }
wait_for "the old slow Pod to go" 180 old_slow_gone
other_blocked() { ! kubectl -n ckad2-net exec frontend -- wget -qO- -T 2 http://other >/dev/null 2>&1; }
wait_for "the NetworkPolicy to block other" 120 other_blocked
