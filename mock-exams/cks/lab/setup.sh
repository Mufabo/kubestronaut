#!/usr/bin/env bash
# Build the exam on the Tier 2 VMs: seven namespaces, two contexts, seeded
# objects, an API server without NodeRestriction, files to work on, and the
# tools the questions need (etcdctl, gVisor, Falco). Repeatable until a question
# that changes the API server's storage or logging is done; after that, restore
# the snapshot on the host.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

require_snapshot "$LAB_SNAPSHOT"
[[ "$(hostname)" == cp1 ]] || die "run this exam on cp1 (envs/vagrant/kbook-vm ssh)"
require_lab_cluster
if sudo grep -qE -- '--(encryption-provider-config|audit-policy-file)' "$APISERVER_MANIFEST"; then
  die "the API server already encrypts or audits (questions 8 and 13). To start over, restore the snapshot on the host: envs/vagrant/kbook-vm restore ${LAB_SNAPSHOT}"
fi
for node in node1 node2; do
  on "$node" true || die "cannot ssh to ${node} from cp1"
done

# ---- tools the questions need -------------------------------------------------------
install_etcdctl
install_gvisor
install_falco

# ---- a clean start -----------------------------------------------------------------
lab_save_kubectx "${STATE}/kubectx"      # keeps the ORIGINAL on repeat runs
mkdir -p "$STATE"
remove_exam
lab_course_reset "$COURSE" {1..15}
C=$COURSE

base="$(base_context)"
cluster="$(ctx_field "$base" cluster)"
user="$(ctx_field "$base" user)"
[[ -n "$cluster" && -n "$user" ]] || die "cannot read the cluster and user of context ${base}"
kubectl config set-context "$CTX_A" --cluster="$cluster" --user="$user" >/dev/null
kubectl config set-context "$CTX_B" --cluster="$cluster" --user="$user" --namespace=cks-prod >/dev/null
for ns in "${NAMESPACES[@]}"; do lab_create_ns "$ns"; done

# ---- question 4: the API server without NodeRestriction -----------------------------
if sudo grep -q -- '--enable-admission-plugins=NodeRestriction$' "$APISERVER_MANIFEST"; then
  info "Turning NodeRestriction off (the API server restarts, about a minute)"
  sudo sed -i 's/--enable-admission-plugins=NodeRestriction$/--enable-admission-plugins=ServiceAccount/' "$APISERVER_MANIFEST"
fi
wait_for "the API server without NodeRestriction" 300 apiserver_restarted_with --enable-admission-plugins=ServiceAccount

# ---- files the questions start from --------------------------------------------------
# Question 2: three copies of kubeadm; two of them have been tampered with.
genuine="kubeadm-$(printf 'abc' | cut -c$((RANDOM % 3 + 1)))"
for f in kubeadm-a kubeadm-b kubeadm-c; do
  cp /usr/bin/kubeadm "${C}/2/${f}"
  [[ "$f" == "$genuine" ]] || printf '\n# patched\n' >> "${C}/2/${f}"
done
chmod 0755 "${C}"/2/kubeadm-*
printf '%s %s\n' "$genuine" "$(sha512sum "${C}/2/${genuine}" | cut -d' ' -f1)" > "${STATE}/genuine"
# Question 5: the AppArmor profile on node2, on disk but not loaded. Its name is
# not its file's name.
# shellcheck disable=SC2029
on node2 "sudo tee ${AA_FILE} >/dev/null" <<EOF
#include <tunables/global>

profile ${AA_PROFILE} flags=(attach_disconnected) {
  #include <abstractions/base>

  file,

  deny /** w,
}
EOF
# Question 6: a seccomp profile that logs every system call.
printf '%s\n' '{"defaultAction": "SCMP_ACT_LOG"}' > "${C}/6/trace.json"
# Question 12: a Dockerfile to fix.
cat > "${C}/12/Dockerfile" <<'EOF'
FROM python:latest
ENV API_TOKEN=tok-7f3a91c2e8d4
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
USER root
CMD ["python", "app.py"]
EOF

# ---- seeded objects ------------------------------------------------------------------
kubectl -n cks-shop apply -f "${MANIFESTS}/shop.yaml" >/dev/null
kubectl -n cks-sys apply -f "${MANIFESTS}/sys.yaml" >/dev/null
kubectl -n cks-pci apply -f "${MANIFESTS}/pci.yaml" >/dev/null
kubectl -n cks-sbx apply -f "${MANIFESTS}/sbx.yaml" >/dev/null
kubectl -n cks-prod apply -f "${MANIFESTS}/prod.yaml" >/dev/null
kubectl -n cks-run apply -f "${MANIFESTS}/run.yaml" >/dev/null

# Question 3: a ServiceAccount with far too much power.
kubectl -n cks-ci create serviceaccount deployer >/dev/null
kubectl create clusterrolebinding deployer-admin --clusterrole=cluster-admin --serviceaccount=cks-ci:deployer >/dev/null

# Question 8: a Secret with a value made up for this run.
card_key="$(head -c 12 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | cut -c1-12)"
printf '%s\n' "$card_key" > "${STATE}/card-key"
kubectl -n cks-pci create secret generic card-keys --from-literal=key="$card_key" >/dev/null

# Question 14: four look-alike Pods on node1; one of them reads /etc/sudoers.
culprit="${SUSPECTS[RANDOM % ${#SUSPECTS[@]}]}"
printf '%s\n' "$culprit" > "${STATE}/culprit"
for s in "${SUSPECTS[@]}"; do
  if [[ "$s" == "$culprit" ]]; then
    # busybox has no /etc/sudoers: write one, then keep reading it.
    script='echo "root ALL=(ALL) ALL" > /etc/sudoers; while true; do cat /etc/sudoers >/dev/null; sleep 20; done'
  else
    script='while true; do cat /etc/hostname >/dev/null; sleep 20; done'
  fi
  payload="$(printf '%s' "$script" | base64 -w0)"
  kubectl -n "${s%%/*}" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: ${s##*/}
spec:
  nodeSelector:
    kubernetes.io/hostname: node1
  containers:
    - name: worker
      image: busybox:1.36
      command: ["sh", "-c", "echo ${payload} | base64 -d | sh"]
      resources:
        requests: {cpu: 10m, memory: 16Mi}
        limits: {memory: 32Mi}
YAML
done

info "Waiting for the seeded Pods and Deployments"
for p in frontend api other; do wait_for "pod ${p} Running" 300 pod_phase_is cks-shop "$p" Running; done
for s in "${SUSPECTS[@]}"; do wait_for "pod ${s} Running" 300 pod_phase_is "${s%%/*}" "${s##*/}" Running; done
kubectl -n cks-sys rollout status deployment/writer --timeout=300s >/dev/null
kubectl -n cks-pci rollout status deployment/payments --timeout=300s >/dev/null
kubectl -n cks-sbx rollout status deployment/untrusted --timeout=300s >/dev/null
kubectl -n cks-prod rollout status deployment/cache --timeout=300s >/dev/null
kubectl -n cks-run rollout status deployment/site --timeout=300s >/dev/null
# Question 11: the digest of the image cache runs now.
digest="$(kubectl -n cks-prod get pods -l app=cache -o jsonpath='{.items[0].status.containerStatuses[0].imageID}')"
printf '%s\n' "${digest##*@}" > "${STATE}/digest"

date +%s > "${STATE}/start"       # the clock starts when setup ends
info "Exam ready. You have ${EXAM_MINUTES} minutes; the pass mark is ${EXAM_PASS_PERCENT}%."
info "Questions: mock-exams/cks/cks.md. Score with: make mock-score EXAM=cks"
