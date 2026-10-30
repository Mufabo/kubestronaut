#!/usr/bin/env bash
# Build the exam on the Tier 2 VMs: six namespaces, two contexts, seeded objects,
# a stopped container runtime on node1, a broken second scheduler, Helm,
# metrics-server, the Gateway API CRDs, and the answer folders. Repeatable: it
# undoes the previous attempt first (a renewed API server certificate stays).
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
for node in node1 node2; do
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$node" true || die "cannot ssh to ${node} from cp1"
done

# ---- tools and add-ons the questions need ----------------------------------------
# Helm (question 2), checked against the release's checksum, as in Chapter 14.
if [[ "$(helm version --short 2>/dev/null)" != "${HELM_VERSION}"* ]]; then
  info "Installing Helm ${HELM_VERSION}"
  tmp="$(mktemp -d)"
  tarball="helm-${HELM_VERSION}-linux-amd64.tar.gz"
  curl -fsSL "https://get.helm.sh/${tarball}" -o "${tmp}/${tarball}"
  curl -fsSL "https://get.helm.sh/${tarball}.sha256sum" -o "${tmp}/${tarball}.sha256sum"
  (cd "$tmp" && sha256sum -c --quiet "${tarball}.sha256sum") || die "checksum mismatch for ${tarball}"
  tar -xzf "${tmp}/${tarball}" -C "$tmp"
  sudo install -m 0755 "${tmp}/linux-amd64/helm" /usr/local/bin/helm
  rm -rf "$tmp"
fi
# metrics-server (question 16). kubeadm's kubelets serve self-signed certificates,
# so it may not verify them, as on kind (tools/cluster.sh).
if ! kubectl -n kube-system get deployment metrics-server >/dev/null 2>&1; then
  info "Installing metrics-server ${METRICS_SERVER_VERSION}"
  kubectl apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml" >/dev/null
  kubectl -n kube-system patch deployment metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' >/dev/null
fi
# The Gateway API (question 8), as in Chapter 12.
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml" >/dev/null
kubectl wait --for=condition=Established crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=60s >/dev/null

# ---- a clean start -----------------------------------------------------------------
lab_save_kubectx "${STATE}/kubectx"      # keeps the ORIGINAL on repeat runs
mkdir -p "$STATE"
# The original Corefile (question 11), saved once so that teardown can put it back.
if [[ ! -s "${STATE}/Corefile" ]]; then
  kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' > "${STATE}/Corefile"
fi
remove_exam
lab_course_reset "$COURSE" {1..18}
C=$COURSE

base="$(base_context)"
cluster="$(ctx_field "$base" cluster)"
user="$(ctx_field "$base" user)"
[[ -n "$cluster" && -n "$user" ]] || die "cannot read the cluster and user of context ${base}"
kubectl config set-context "$CTX_A" --cluster="$cluster" --user="$user" >/dev/null
kubectl config set-context "$CTX_B" --cluster="$cluster" --user="$user" --namespace=cka-work >/dev/null

# Question 14: node1's container runtime is stopped and disabled. Broken first,
# so that every seeded workload below lands on node2.
# A repeated setup has just started containerd again (remove_exam): wait until node1
# is Ready, or it could turn Ready, and take Pods, after the check below.
wait_for "node1 Ready before the fault" 300 node_ready node1
on node1 "sudo systemctl disable --now containerd" >/dev/null 2>&1 || true
# NotReady, and tainted so that the scheduler sends nothing there.
node1_out() {
  ! node_ready node1 &&
    [[ "$(kubectl get node node1 -o jsonpath='{.spec.taints[*].key}' 2>/dev/null)" == *node.kubernetes.io/not-ready* ]]
}
info "Waiting for node1 to go NotReady (about a minute)"
wait_for "node1 NotReady and tainted" 300 node1_out

for ns in "${NAMESPACES[@]}"; do
  [[ "$ns" == cka-infra ]] || lab_create_ns "$ns"      # question 2 creates cka-infra
done
kubectl label namespace cka-team purpose=partners --overwrite >/dev/null    # question 9

# ---- files the questions start from --------------------------------------------------
# Question 1: jane's key and certificate signing request.
openssl genrsa -out "${C}/1/jane.key" 2048 2>/dev/null
openssl req -new -key "${C}/1/jane.key" -subj "/CN=jane/O=cka-devs" -out "${C}/1/jane.csr" 2>/dev/null
# Question 2: the chart to install.
cp -r "${here}/../../../chapters/14-helm-kustomize/manifests/charts/shop" "${C}/2/chart"
# Question 3: the serial of the API server certificate before the exam.
serial="$(sudo openssl x509 -noout -serial -in /etc/kubernetes/pki/apiserver.crt)"
printf '%s\n' "$serial" > "${STATE}/apiserver-serial"
# Question 12: the directory for the local volume.
on node2 "sudo mkdir -p /srv/cka-fast" >/dev/null

# ---- seeded objects ------------------------------------------------------------------
kubectl -n cka-net apply -f "${MANIFESTS}/net.yaml" >/dev/null
kubectl apply -f "${MANIFESTS}/gateway.yaml" >/dev/null
kubectl -n cka-team apply -f "${MANIFESTS}/team.yaml" >/dev/null
kubectl -n cka-work apply -f "${MANIFESTS}/work.yaml" >/dev/null
kubectl -n cka-ops apply -f "${MANIFESTS}/ops.yaml" >/dev/null

# Question 7: portal has three revisions; the first ran nginx:1.25.
kubectl -n cka-work create deployment portal --image=nginx:1.25 --replicas=2 >/dev/null
kubectl -n cka-work rollout status deployment/portal --timeout=300s >/dev/null
for tag in 1.26 1.27; do
  kubectl -n cka-work set image deployment/portal nginx="nginx:${tag}" >/dev/null
  kubectl -n cka-work rollout status deployment/portal --timeout=300s >/dev/null
done

# Question 13: a static volume that would be deleted with its claim.
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: archive-pv
spec:
  capacity:
    storage: 1Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Delete
  storageClassName: manual
  hostPath:
    path: /srv/cka-archive
    type: DirectoryOrCreate
YAML

# Question 15: a second scheduler whose configuration names a kubeconfig that
# does not exist.
sudo tee "$SCHED_CONFIG" >/dev/null <<'YAML'
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: /etc/kubernetes/schedular.conf
leaderElection:
  leaderElect: false
profiles:
  - schedulerName: cka-scheduler
YAML
sudo tee "$SCHED_MANIFEST" >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: cka-scheduler
  namespace: cka-ops
  labels:
    component: cka-scheduler
spec:
  hostNetwork: true
  containers:
    - name: cka-scheduler
      image: registry.k8s.io/kube-scheduler:${K8S_VERSION}
      command:
        - kube-scheduler
        - --config=${SCHED_CONFIG}
        - --secure-port=10269
      volumeMounts:
        - name: kubeconfig
          mountPath: /etc/kubernetes/scheduler.conf
          readOnly: true
        - name: config
          mountPath: ${SCHED_CONFIG}
          readOnly: true
  volumes:
    - name: kubeconfig
      hostPath:
        path: /etc/kubernetes/scheduler.conf
        type: FileOrCreate
    - name: config
      hostPath:
        path: ${SCHED_CONFIG}
        type: FileOrCreate
YAML

info "Waiting for the seeded Pods and Deployments"
wait_for "pod local Running" 300 pod_phase_is cka-net local Running
for p in caller stranger; do wait_for "pod ${p} Running" 300 pod_phase_is cka-team "$p" Running; done
for p in client meter-a meter-b meter-c; do wait_for "pod ${p} Running" 300 pod_phase_is cka-ops "$p" Running; done
for d in backend legacy web; do kubectl -n cka-net rollout status "deployment/${d}" --timeout=300s >/dev/null; done
kubectl -n cka-work rollout status deployment/api --timeout=300s >/dev/null
kubectl -n kube-system rollout status deployment/metrics-server --timeout=300s >/dev/null

date +%s > "${STATE}/start"       # the clock starts when setup ends
info "Exam ready. You have ${EXAM_MINUTES} minutes; the pass mark is ${EXAM_PASS_PERCENT}%."
info "Questions: mock-exams/cka/cka.md. Score with: make mock-score EXAM=cka"
