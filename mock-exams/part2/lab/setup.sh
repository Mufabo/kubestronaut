#!/usr/bin/env bash
# Build the exam: six namespaces, two contexts, seeded objects, answer folders.
# Idempotent: it always removes the previous attempt first.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

require_lab_cluster
lab_save_kubectx "${STATE}/kubectx"      # keeps the ORIGINAL on repeat runs
remove_exam
mkdir -p "$STATE"
lab_course_reset "$COURSE" 1 2 3 4 5 6 7 8 9 10 11 12 13 14

base="$(base_context)"
cluster="$(ctx_field "$base" cluster)"
user="$(ctx_field "$base" user)"
[[ -n "$cluster" && -n "$user" ]] || die "cannot read the cluster and user of context ${base}"
kubectl config set-context "$CTX_A" --cluster="$cluster" --user="$user" >/dev/null
kubectl config set-context "$CTX_B" --cluster="$cluster" --user="$user" --namespace=p2-batch >/dev/null

for ns in "${NAMESPACES[@]}"; do lab_create_ns "$ns"; done

# Question 10: the chart the reader installs, copied where the question says.
cp -r "${here}/../../../chapters/14-helm-kustomize/manifests/charts/shop" "${COURSE}/10/chart"

# Question 8: shop runs, but its Service selects the wrong label.
kubectl -n p2-edge create deployment shop --image=nginx:1.27 --replicas=2 >/dev/null
kubectl -n p2-edge apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: shop
spec:
  selector:
    app: shp
  ports:
    - port: 80
      targetPort: 80
YAML

# Question 11: api has two revisions; the last one is the one to roll back from.
kubectl -n p2-release create deployment api --image=nginx:1.26 --replicas=2 >/dev/null
kubectl -n p2-release rollout status deployment/api --timeout=180s >/dev/null
kubectl -n p2-release set image deployment/api nginx=nginx:1.27 >/dev/null
kubectl -n p2-release rollout status deployment/api --timeout=180s >/dev/null

# Question 12: a Pod that fails and prints the line the answer file needs.
kubectl -n p2-ops apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: crash
spec:
  containers:
    - name: crash
      image: busybox:1.36
      command: ["sh", "-c", "echo 'fatal: license expired'; exit 2"]
YAML

# Question 14: three Pods labelled stage=old, and one that must not change.
for i in 1 2 3; do
  kubectl -n p2-ops run "tool-${i}" --image=busybox:1.36 --labels=stage=old -- sleep 3600 >/dev/null
done
kubectl -n p2-ops run keep --image=busybox:1.36 --labels=stage=keep -- sleep 3600 >/dev/null

info "Waiting for the seeded Pods and Deployments"
kubectl -n p2-edge rollout status deployment/shop --timeout=180s >/dev/null
for p in tool-1 tool-2 tool-3 keep; do wait_for "pod ${p} Running" 180 pod_phase_is p2-ops "$p" Running; done

date +%s > "${STATE}/start"       # the clock starts when setup ends
info "Exam ready. You have ${EXAM_MINUTES} minutes; the pass mark is ${EXAM_PASS_PERCENT}%."
info "Questions: mock-exams/part2/part2.md. Score with: make mock-score EXAM=part2"
