#!/usr/bin/env bash
# shellcheck disable=SC2029  # variables in ssh commands are meant to expand on cp1
# Build the exam on the Tier 2 VMs: nine namespaces, two contexts, seeded objects,
# a kubelet on node2 that cannot start, Helm releases (one failed), a CRD, the
# Gateway API, etcdctl, and the answer folders. Repeatable: it undoes the
# previous attempt first.
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
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ---- tools the questions need --------------------------------------------------------
if [[ "$(helm version --short 2>/dev/null)" != "${HELM_VERSION}"* ]]; then
  info "Installing Helm ${HELM_VERSION}"
  tarball="helm-${HELM_VERSION}-linux-amd64.tar.gz"
  curl -fsSL "https://get.helm.sh/${tarball}" -o "${tmp}/${tarball}"
  curl -fsSL "https://get.helm.sh/${tarball}.sha256sum" -o "${tmp}/${tarball}.sha256sum"
  (cd "$tmp" && sha256sum -c --quiet "${tarball}.sha256sum") || die "checksum mismatch for ${tarball}"
  tar -xzf "${tmp}/${tarball}" -C "$tmp"
  sudo install -m 0755 "${tmp}/linux-amd64/helm" /usr/local/bin/helm
fi
if [[ "$(etcdutl version 2>/dev/null | head -1)" != "etcdutl version: ${ETCD_VERSION#v}" ]]; then
  info "Installing etcdctl and etcdutl ${ETCD_VERSION}"
  base="https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}"
  tarball="etcd-${ETCD_VERSION}-linux-amd64.tar.gz"
  curl -fsSL "${base}/${tarball}" -o "${tmp}/${tarball}"
  curl -fsSL "${base}/SHA256SUMS" -o "${tmp}/SHA256SUMS"
  (cd "$tmp" && grep " ${tarball}$" SHA256SUMS | sha256sum -c --quiet -) || die "checksum mismatch for ${tarball}"
  tar -xzf "${tmp}/${tarball}" -C "$tmp"
  sudo install -m 0755 "${tmp}/etcd-${ETCD_VERSION}-linux-amd64/etcdctl" "${tmp}/etcd-${ETCD_VERSION}-linux-amd64/etcdutl" /usr/local/bin/
fi
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml" >/dev/null
kubectl wait --for=condition=Established crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=60s >/dev/null

# ---- a clean start ---------------------------------------------------------------------
lab_save_kubectx "${STATE}/kubectx"      # keeps the ORIGINAL on repeat runs
mkdir -p "$STATE"
remove_exam
lab_course_reset "$COURSE" {1..18}
C=$COURSE

base="$(base_context)"
cluster="$(ctx_field "$base" cluster)"
user="$(ctx_field "$base" user)"
[[ -n "$cluster" && -n "$user" ]] || die "cannot read the cluster and user of context ${base}"
kubectl config set-context "$CTX_A" --cluster="$cluster" --user="$user" >/dev/null
kubectl config set-context "$CTX_B" --cluster="$cluster" --user="$user" --namespace=cka2-work >/dev/null

# Question 14: node2's kubelet points at a client CA file that does not exist. Broken
# first, so that every seeded workload lands on node1. A repeated setup has just
# repaired it (remove_exam): wait until node2 is Ready, or it could turn Ready, and
# take Pods, after the check below.
wait_for "node2 Ready before the fault" 300 node_ready node2
on node2 "sudo sed -i 's|clientCAFile: /etc/kubernetes/pki/ca.crt|clientCAFile: /etc/kubernetes/pki/ca-cert.crt|' ${KUBELET_CONFIG} && sudo systemctl restart kubelet" >/dev/null 2>&1 || true
node2_out() {
  ! node_ready node2 &&
    [[ "$(kubectl get node node2 -o jsonpath='{.spec.taints[*].key}' 2>/dev/null)" == *node.kubernetes.io/* ]]
}
info "Waiting for node2 to go NotReady (about a minute)"
wait_for "node2 NotReady and tainted" 300 node2_out

for ns in "${NAMESPACES[@]}"; do lab_create_ns "$ns"; done

# ---- files the questions start from ------------------------------------------------------
# Question 3: the metrics-server release manifest, to install with Kustomize.
curl -fsSL "https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml" \
  -o "${C}/3/components.yaml"

# Question 4: a chart; two working releases, one failed.
cp -r "${here}/../../../chapters/14-helm-kustomize/manifests/charts/shop" "${C}/4/chart"
helm -n cka2-apps install web "${C}/4/chart" --wait --timeout 180s >/dev/null
helm -n cka2-apps install api "${C}/4/chart" --wait --timeout 180s >/dev/null
helm -n cka2-legacy install jobs "${C}/4/chart" --set image.tag=0.0-missing --wait --timeout 20s >/dev/null 2>&1 || true

# Question 15: a kubeconfig for the user ops, with the wrong CA.
openssl genrsa -out "${tmp}/ops.key" 2048 2>/dev/null
openssl req -new -key "${tmp}/ops.key" -subj "/CN=ops" -out "${tmp}/ops.csr" 2>/dev/null
sudo openssl x509 -req -in "${tmp}/ops.csr" -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key \
  -CAcreateserial -CAserial "${tmp}/ca.srl" -days 30 -out "${tmp}/ops.crt" 2>/dev/null
sudo chown "$(id -u):$(id -g)" "${tmp}/ops.crt"
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=other-ca" -keyout "${tmp}/other.key" -out "${tmp}/other-ca.crt" 2>/dev/null
k="${C}/15/ops.kubeconfig"
kubectl config --kubeconfig="$k" set-cluster kbook-vm --server="https://${CP_IP}:6443" \
  --certificate-authority="${tmp}/other-ca.crt" --embed-certs=true >/dev/null
kubectl config --kubeconfig="$k" set-credentials ops --client-certificate="${tmp}/ops.crt" \
  --client-key="${tmp}/ops.key" --embed-certs=true >/dev/null
kubectl config --kubeconfig="$k" set-context ops --cluster=kbook-vm --user=ops --namespace=cka2-ops >/dev/null
kubectl config --kubeconfig="$k" use-context ops >/dev/null
kubectl config --kubeconfig="$k" view --raw -o jsonpath='{.users[0].user.client-certificate-data}' > "${STATE}/ops-cert"

# ---- seeded objects -------------------------------------------------------------------------
kubectl apply -f "${MANIFESTS}/cluster.yaml" >/dev/null
kubectl wait --for=condition=Established "crd/${REPORTS_CRD}" --timeout=60s >/dev/null
kubectl -n cka2-team apply -f "${MANIFESTS}/team.yaml" >/dev/null
kubectl -n cka2-work apply -f "${MANIFESTS}/work.yaml" >/dev/null
kubectl -n cka2-net apply -f "${MANIFESTS}/net.yaml" >/dev/null
kubectl -n cka2-locked apply -f "${MANIFESTS}/locked.yaml" >/dev/null
kubectl -n cka2-data apply -f "${MANIFESTS}/data.yaml" >/dev/null
kubectl -n cka2-ops apply -f "${MANIFESTS}/ops.yaml" >/dev/null

# Questions 12 and 13: the hostPath directories on node1, and the shared log.
on node1 "sudo mkdir -p /srv/cka2-archive /srv/cka2-reports /srv/cka2-shared/logs && echo 'cka2 shared log' | sudo tee /srv/cka2-shared/logs/app.log >/dev/null"

# Question 16: cruncher fails once, with a token made up for this run, then recovers.
token="$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
printf '%s\n' "$token" > "${STATE}/token"
kubectl -n cka2-ops apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: cruncher
spec:
  volumes:
    - name: state
      emptyDir: {}
  containers:
    - name: cruncher
      image: busybox:1.36
      env:
        - name: TOKEN
          value: "${token}"
      command:
        - sh
        - -c
        - 'if [ -f /state/ran ]; then echo recovered; sleep infinity; else touch /state/ran; echo "fatal: token \$TOKEN rejected"; exit 1; fi'
      volumeMounts:
        - name: state
          mountPath: /state
YAML

info "Waiting for the seeded Pods and Deployments"
for p in a b; do wait_for "pod ${p} Running" 300 pod_phase_is cka2-locked "$p" Running; done
for p in client outsider; do wait_for "pod ${p} Running" 300 pod_phase_is cka2-net "$p" Running; done
kubectl -n cka2-net rollout status deployment/api --timeout=300s >/dev/null
cruncher_recovered() {
  [[ "$(kubectl -n cka2-ops get pod cruncher -o jsonpath='{.status.containerStatuses[0].restartCount}/{.status.phase}' 2>/dev/null)" == 1/Running ]]
}
wait_for "pod cruncher to fail once and recover" 300 cruncher_recovered

date +%s > "${STATE}/start"       # the clock starts when setup ends
info "Exam ready. You have ${EXAM_MINUTES} minutes; the pass mark is ${EXAM_PASS_PERCENT}%."
info "Questions: mock-exams/cka2/cka2.md. Score with: make mock-score EXAM=cka2"
