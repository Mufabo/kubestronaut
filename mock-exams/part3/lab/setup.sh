#!/usr/bin/env bash
# Build the exam on the Tier 2 VMs: five namespaces, two contexts, seeded objects,
# a broken kubelet on node2, the etcd client tools, and the answer folders.
# Repeatable while the cluster is still at K8S_PREV_VERSION; after the upgrade
# question has been answered, only a snapshot restore resets the exam.
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
if [[ "$(kubectl -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}')" != *"kubernetesVersion: ${K8S_PREV_VERSION}"* ]]; then
  die "the control plane is no longer at ${K8S_PREV_VERSION}. To start over, restore the snapshot on the host: envs/vagrant/kbook-vm restore ${LAB_SNAPSHOT}"
fi

# etcdctl and etcdutl (Question 6), as in Chapter 20, checked against the release's checksums.
if [[ "$(etcdutl version 2>/dev/null | head -1)" != "etcdutl version: ${ETCD_VERSION#v}" ]]; then
  info "Installing etcdctl and etcdutl ${ETCD_VERSION}"
  tmp="$(mktemp -d)"
  base="https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}"
  tarball="etcd-${ETCD_VERSION}-linux-amd64.tar.gz"
  curl -fsSL "${base}/${tarball}" -o "${tmp}/${tarball}"
  curl -fsSL "${base}/SHA256SUMS" -o "${tmp}/SHA256SUMS"
  (cd "$tmp" && grep " ${tarball}$" SHA256SUMS | sha256sum -c --quiet -) || die "checksum mismatch for ${tarball}"
  tar -xzf "${tmp}/${tarball}" -C "$tmp"
  sudo install -m 0755 "${tmp}/etcd-${ETCD_VERSION}-linux-amd64/etcdctl" "${tmp}/etcd-${ETCD_VERSION}-linux-amd64/etcdutl" /usr/local/bin/
  rm -rf "$tmp"
fi

lab_save_kubectx "${STATE}/kubectx"      # keeps the ORIGINAL on repeat runs
remove_exam
mkdir -p "$STATE"
lab_course_reset "$COURSE" 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16

base="$(base_context)"
cluster="$(ctx_field "$base" cluster)"
user="$(ctx_field "$base" user)"
[[ -n "$cluster" && -n "$user" ]] || die "cannot read the cluster and user of context ${base}"
kubectl config set-context "$CTX_A" --cluster="$cluster" --user="$user" >/dev/null
kubectl config set-context "$CTX_B" --cluster="$cluster" --user="$user" --namespace=p3-apps >/dev/null

# Question 15: node2's kubelet points at a binary that does not exist. Broken
# first, so the seeded workloads below all land on node1.
on node2 "sudo sed -i 's|^ExecStart=/usr/bin/kubelet |ExecStart=/usr/local/bin/kubelet |' ${DROPIN} && sudo systemctl daemon-reload && sudo systemctl restart kubelet" >/dev/null 2>&1 || true
node_not_ready() { ! node_ready "$1"; }
info "Waiting for the exam's faults to show (about a minute)"
wait_for "node2 NotReady" 300 node_not_ready node2

for ns in "${NAMESPACES[@]}"; do lab_create_ns "$ns"; done
kubectl apply -f "${MANIFESTS}/crd.yaml" >/dev/null
kubectl -n p3-net apply -f "${MANIFESTS}/net.yaml" >/dev/null
kubectl -n p3-apps apply -f "${MANIFESTS}/apps.yaml" >/dev/null

# Question 6: the backup must be newer than this point.
kubectl -n p3-ops create configmap marker --from-literal=exam=part3 >/dev/null
kubectl -n p3-ops get configmap marker -o jsonpath='{.metadata.resourceVersion}' > "${STATE}/marker-rv"

info "Waiting for the seeded Pods and Deployments"
for p in db api other; do wait_for "pod ${p} Running" 300 pod_phase_is p3-net "$p" Running; done
wait_for "pod probe Running" 300 pod_phase_is p3-apps probe Running
kubectl -n p3-apps rollout status deployment/web --timeout=300s >/dev/null
kubectl -n p3-apps rollout status deployment/shop --timeout=300s >/dev/null

date +%s > "${STATE}/start"       # the clock starts when setup ends
info "Exam ready. You have ${EXAM_MINUTES} minutes; the pass mark is ${EXAM_PASS_PERCENT}%."
info "Questions: mock-exams/part3/part3.md. Score with: make mock-score EXAM=part3"
