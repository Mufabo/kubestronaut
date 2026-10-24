#!/usr/bin/env bash
# Build the exam: six namespaces, two contexts, a CRD, seeded objects and
# files, answer folders. Idempotent: it always removes the previous attempt first.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

require_lab_cluster
require_cmd helm
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
kubectl config set-context "$CTX_B" --cluster="$cluster" --user="$user" --namespace=ckad-deploy >/dev/null

for ns in "${NAMESPACES[@]}"; do lab_create_ns "$ns"; done

# ---- files the questions start from ---------------------------------------------
# Question 1: the app to rebuild.
mkdir -p "${C}/1/app"
cat > "${C}/1/app/Dockerfile" <<'EOF'
FROM busybox:1.36
ENV APP_VERSION=1.0
COPY run.sh /run.sh
CMD ["sh", "/run.sh"]
EOF
cat > "${C}/1/app/run.sh" <<'EOF'
echo "ckad-web version ${APP_VERSION}"
sleep 3600
EOF

# Question 2: the Pod to extend with a sidecar.
cat > "${C}/2/logger.yaml" <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: logger
  namespace: ckad-design
spec:
  volumes:
    - name: logs
      emptyDir: {}
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "i=0; while true; do i=$((i+1)); echo \"order $i\" >> /var/log/app/app.log; sleep 2; done"]
      volumeMounts:
        - name: logs
          mountPath: /var/log/app
EOF

# Question 7: the chart of the release.
cp -r "${here}/../../../chapters/14-helm-kustomize/manifests/charts/shop" "${C}/7/chart"

# Question 8: the Kustomize base.
mkdir -p "${C}/8/base" "${C}/8/overlays/prod"
cat > "${C}/8/base/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ledger
  labels:
    app: ledger
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ledger
  template:
    metadata:
      labels:
        app: ledger
    spec:
      containers:
        - name: ledger
          image: nginx:1.27
EOF
cat > "${C}/8/base/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
EOF

# Question 9: a manifest written for an API version the cluster no longer serves.
cat > "${C}/9/cleanup.yaml" <<'EOF'
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: cleanup
  namespace: ckad-ops
spec:
  schedule: "*/30 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: cleanup
              image: busybox:1.36
              command: ["sh", "-c", "echo cleanup"]
EOF

# Question 13: the properties file for the ConfigMap.
printf 'host=db.ckad-sec.svc\nport=5432\n' > "${C}/13/db.properties"

# ---- ckad-deploy -------------------------------------------------------------------
# Question 5: frontend runs the old image with the default strategy.
kubectl -n ckad-deploy create deployment frontend --image=nginx:1.26 --replicas=4 >/dev/null

# Question 6: the stable checkout, and the Service in front of it.
kubectl -n ckad-deploy apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout
spec:
  replicas: 4
  selector:
    matchLabels:
      app: checkout
      track: stable
  template:
    metadata:
      labels:
        app: checkout
        track: stable
    spec:
      containers:
        - name: checkout
          image: nginx:1.26
---
apiVersion: v1
kind: Service
metadata:
  name: checkout
spec:
  selector:
    app: checkout
  ports:
    - port: 80
      targetPort: 80
YAML

# Question 7: the release, installed with one custom value.
helm -n ckad-deploy install cache "${C}/7/chart" --set greeting=hello-ckad --wait --timeout 180s >/dev/null

# ---- ckad-ops ----------------------------------------------------------------------
# Question 10: api runs without probes.
kubectl -n ckad-ops create deployment api --image=nginx:1.27 --replicas=2 >/dev/null

# Question 11: two containers print lines; only the worker's errors count.
kubectl -n ckad-ops apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: batch-runner
spec:
  containers:
    - name: fetch
      image: busybox:1.36
      command: ["sh", "-c", "echo 'INFO fetching'; echo 'ERROR fetch is not the worker'; sleep 3600"]
    - name: worker
      image: busybox:1.36
      command: ["sh", "-c", "echo 'INFO start'; echo 'ERROR disk full on /data'; echo 'INFO retrying'; echo 'ERROR retry limit reached'; echo 'INFO done'; sleep 3600"]
YAML

# Question 12: reports looks for a file its ConfigMap names differently.
kubectl -n ckad-ops apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: reports-config
data:
  settings.cfg: |
    format=pdf
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reports
spec:
  replicas: 1
  selector:
    matchLabels:
      app: reports
  template:
    metadata:
      labels:
        app: reports
    spec:
      volumes:
        - name: config
          configMap:
            name: reports-config
      containers:
        - name: reports
          image: busybox:1.36
          command: ["sh", "-c", "test -f /config/settings.conf || { echo 'missing /config/settings.conf'; exit 1; }; sleep 3600"]
          volumeMounts:
            - name: config
              mountPath: /config
YAML

# ---- ckad-quota --------------------------------------------------------------------
# Question 16: the quota requires requests and limits, and burst sets none.
kubectl -n ckad-quota apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute
spec:
  hard:
    pods: "5"
    requests.cpu: "1"
    requests.memory: 1Gi
    limits.cpu: "2"
    limits.memory: 2Gi
YAML
kubectl -n ckad-quota create deployment burst --image=busybox:1.36 --replicas=3 -- sleep 3600 >/dev/null

# ---- the CRD (question 17) ---------------------------------------------------------
kubectl apply -f - >/dev/null <<YAML
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: ${CKAD_CRD}
spec:
  group: ckad.kbook.io
  scope: Namespaced
  names:
    plural: caches
    singular: cache
    kind: Cache
    shortNames: [cch]
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
                  type: string
                  enum: [small, medium, large]
                replicas:
                  type: integer
                  minimum: 1
                  maximum: 5
YAML
kubectl wait --for=condition=Established "crd/${CKAD_CRD}" --timeout=60s >/dev/null

# ---- ckad-net ----------------------------------------------------------------------
# Question 18: catalog names its port http; the Service asks for web.
kubectl -n ckad-net apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
spec:
  replicas: 2
  selector:
    matchLabels:
      app: catalog
  template:
    metadata:
      labels:
        app: catalog
    spec:
      containers:
        - name: catalog
          image: nginx:1.27
          ports:
            - name: http
              containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: catalog
spec:
  selector:
    app: catalog
  ports:
    - port: 80
      targetPort: web
YAML

# Questions 18 and 19: a client for each test, and the database.
kubectl -n ckad-net run probe --image=busybox:1.36 --labels=app=probe -- sleep 3600 >/dev/null
kubectl -n ckad-net run db --image=nginx:1.27 --labels=app=db >/dev/null
kubectl -n ckad-net run api --image=busybox:1.36 --labels=app=api -- sleep 3600 >/dev/null
kubectl -n ckad-net run web --image=busybox:1.36 --labels=app=web -- sleep 3600 >/dev/null
kubectl -n ckad-net expose pod db --port=80 >/dev/null

# Question 20: two apps; shop already has a Service, cart does not.
kubectl -n ckad-net create deployment shop --image=nginx:1.27 --replicas=2 >/dev/null
kubectl -n ckad-net expose deployment shop --port=80 >/dev/null
kubectl -n ckad-net create deployment cart --image=nginx:1.27 --replicas=2 >/dev/null

info "Waiting for the seeded Pods and Deployments"
for d in frontend checkout; do kubectl -n ckad-deploy rollout status "deployment/${d}" --timeout=180s >/dev/null; done
kubectl -n ckad-ops rollout status deployment/api --timeout=180s >/dev/null
for d in catalog shop cart; do kubectl -n ckad-net rollout status "deployment/${d}" --timeout=180s >/dev/null; done
for p in probe db api web; do wait_for "pod ${p} Running" 180 pod_phase_is ckad-net "$p" Running; done
wait_for "pod batch-runner Running" 180 pod_phase_is ckad-ops batch-runner Running

date +%s > "${STATE}/start"       # the clock starts when setup ends
info "Exam ready. You have ${EXAM_MINUTES} minutes; the pass mark is ${EXAM_PASS_PERCENT}%."
info "Questions: mock-exams/ckad/ckad.md. Score with: make mock-score EXAM=ckad"
