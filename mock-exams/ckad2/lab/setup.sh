#!/usr/bin/env bash
# Build the exam: six namespaces, two contexts, seeded objects and files,
# answer folders. Idempotent: it always removes the previous attempt first.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

require_lab_cluster
require_cmd helm openssl
lab_save_kubectx "${STATE}/kubectx"      # keeps the ORIGINAL on repeat runs
remove_exam
mkdir -p "$STATE"
lab_course_reset "$COURSE" {1..20}
C=$COURSE

base="$(base_context)"
cluster="$(ctx_field "$base" cluster)"
user="$(ctx_field "$base" user)"
[[ -n "$cluster" && -n "$user" ]] || die "cannot read the cluster and user of context ${base}"
kubectl config set-context "$CTX_A" --cluster="$cluster" --user="$user" >/dev/null
kubectl config set-context "$CTX_B" --cluster="$cluster" --user="$user" --namespace=ckad2-deploy >/dev/null

for ns in "${NAMESPACES[@]}"; do lab_create_ns "$ns"; done

# ---- files the questions start from ---------------------------------------------
# Question 1: an image that runs as root and declares no port.
mkdir -p "${C}/1/app"
cat > "${C}/1/app/Dockerfile" <<'EOF'
FROM busybox:1.36
COPY serve.sh /serve.sh
CMD ["sh", "/serve.sh"]
EOF
cat > "${C}/1/app/serve.sh" <<'EOF'
echo "ckad2-api listening on 8080"
exec httpd -f -p 8080 -h /
EOF

# Question 8: a Kustomize base with a generated ConfigMap, and an empty overlay.
mkdir -p "${C}/8/base" "${C}/8/overlays/staging"
cat > "${C}/8/base/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels:
    app: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx:1.26
          envFrom:
            - configMapRef:
                name: app-config
EOF
cat > "${C}/8/base/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
configMapGenerator:
  - name: app-config
    literals:
      - MODE=base
EOF

# Question 9: an HPA written for a removed API version.
cat > "${C}/9/hpa.yaml" <<'EOF'
apiVersion: autoscaling/v2beta2
kind: HorizontalPodAutoscaler
metadata:
  name: api
  namespace: ckad2-ops
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 1
  maxReplicas: 3
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
EOF

# Question 15: a certificate and key for the TLS Secret.
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=web.ckad2.example.test" \
  -keyout "${C}/15/tls.key" -out "${C}/15/tls.crt" 2>/dev/null

# ---- ckad2-deploy --------------------------------------------------------------
# Question 5: reports uses the default rolling update.
kubectl -n ckad2-deploy create deployment reports --image=nginx:1.26 --replicas=2 >/dev/null

# Question 6: blue serves, green is ready but idle.
for color in blue green; do
  tag=1.26; [[ "$color" == green ]] && tag=1.27
  kubectl -n ckad2-deploy apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-${color}
spec:
  replicas: 3
  selector:
    matchLabels:
      app: shop
      version: ${color}
  template:
    metadata:
      labels:
        app: shop
        version: ${color}
    spec:
      containers:
        - name: shop
          image: nginx:${tag}
YAML
done
kubectl -n ckad2-deploy apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: shop
spec:
  selector:
    app: shop
    version: blue
  ports:
    - port: 80
YAML

# Question 7: catalog at revision 1 works; revision 2 points at an image that does not exist.
rm -rf "${STATE}/chart"
cp -r "${here}/../../../chapters/14-helm-kustomize/manifests/charts/shop" "${STATE}/chart"
helm -n ckad2-deploy install catalog "${STATE}/chart" --set image.tag=1.26 --wait --timeout 180s >/dev/null
helm -n ckad2-deploy upgrade catalog "${STATE}/chart" --reuse-values --set image.tag=1.99-missing >/dev/null

# ---- ckad2-ops -----------------------------------------------------------------
kubectl -n ckad2-ops apply -f - >/dev/null <<'YAML'
# Question 9: the HPA's target.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: api
          image: nginx:1.27
          resources:
            requests:
              cpu: 50m
---
# Question 10: ready after 30 seconds, but the liveness probe gives up after 15.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: slow
spec:
  replicas: 1
  selector:
    matchLabels:
      app: slow
  template:
    metadata:
      labels:
        app: slow
    spec:
      containers:
        - name: slow
          image: busybox:1.36
          command: ["sh", "-c", "sleep 30; touch /tmp/ready; sleep infinity"]
          livenessProbe:
            exec:
              command: ["cat", "/tmp/ready"]
            periodSeconds: 5
---
# Question 11: one Pod burns CPU, two idle.
apiVersion: v1
kind: Pod
metadata:
  name: burner
  labels:
    app: load
spec:
  containers:
    - name: load
      image: busybox:1.36
      command: ["sh", "-c", "while true; do :; done"]
      resources:
        limits:
          cpu: 200m
---
apiVersion: v1
kind: Pod
metadata:
  name: idler-1
  labels:
    app: load
spec:
  containers:
    - name: load
      image: busybox:1.36
      command: ["sleep", "infinity"]
---
apiVersion: v1
kind: Pod
metadata:
  name: idler-2
  labels:
    app: load
spec:
  containers:
    - name: load
      image: busybox:1.36
      command: ["sleep", "infinity"]
---
# Question 12: the Pod needs a key the ConfigMap does not have.
apiVersion: v1
kind: ConfigMap
metadata:
  name: client-config
data:
  TIMEOUT: "5"
---
apiVersion: v1
kind: Pod
metadata:
  name: api-client
spec:
  containers:
    - name: client
      image: busybox:1.36
      command: ["sh", "-c", "echo calling $API_URL; sleep infinity"]
      env:
        - name: API_URL
          valueFrom:
            configMapKeyRef:
              name: client-config
              key: API_URL
YAML

# ---- ckad2-net -----------------------------------------------------------------
kubectl -n ckad2-net apply -f - >/dev/null <<'YAML'
# Question 18: backend's Service port is 8080, its Pods listen on 80.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
        - name: backend
          image: nginx:1.27
---
apiVersion: v1
kind: Service
metadata:
  name: backend
spec:
  selector:
    app: backend
  ports:
    - port: 8080
      targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: other
spec:
  replicas: 1
  selector:
    matchLabels:
      app: other
  template:
    metadata:
      labels:
        app: other
    spec:
      containers:
        - name: other
          image: nginx:1.27
---
apiVersion: v1
kind: Service
metadata:
  name: other
spec:
  selector:
    app: other
  ports:
    - port: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  containers:
    - name: frontend
      image: busybox:1.36
      command: ["sleep", "infinity"]
---
# Question 19: legacy has no Service yet.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy
spec:
  replicas: 2
  selector:
    matchLabels:
      app: legacy
  template:
    metadata:
      labels:
        app: legacy
    spec:
      containers:
        - name: legacy
          image: nginx:1.27
---
# Question 20: the Ingress's backends.
apiVersion: v1
kind: Service
metadata:
  name: api
spec:
  selector:
    app: legacy
  ports:
    - port: 80
---
apiVersion: v1
kind: Service
metadata:
  name: fallback
spec:
  selector:
    app: other
  ports:
    - port: 80
YAML
# Question 20: the TLS Secret the Ingress names.
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=portal.ckad2.example.test" \
  -keyout "${STATE}/portal.key" -out "${STATE}/portal.crt" 2>/dev/null
kubectl -n ckad2-net create secret tls portal-tls --cert="${STATE}/portal.crt" --key="${STATE}/portal.key" >/dev/null

info "Waiting for the seeded Pods and Deployments"
for d in reports shop-blue shop-green; do kubectl -n ckad2-deploy rollout status "deployment/${d}" --timeout=180s >/dev/null; done
kubectl -n ckad2-ops rollout status deployment/api --timeout=180s >/dev/null
for d in backend other legacy; do kubectl -n ckad2-net rollout status "deployment/${d}" --timeout=180s >/dev/null; done
for p in burner idler-1 idler-2; do wait_for "pod ${p} Running" 180 pod_phase_is ckad2-ops "$p" Running; done
wait_for "pod frontend Running" 180 pod_phase_is ckad2-net frontend Running

date +%s > "${STATE}/start"       # the clock starts when setup ends
info "Exam ready. You have ${EXAM_MINUTES} minutes; the pass mark is ${EXAM_PASS_PERCENT}%."
info "Questions: mock-exams/ckad2/ckad2.md. Score with: make mock-score EXAM=ckad2"
