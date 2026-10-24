#!/usr/bin/env bash
# shellcheck disable=SC2029  # variables in ssh commands are meant to expand on cp1
# Tier 2: the starting state is the cluster snapshot, kube-bench on cp1 and node2,
# a careless kubelet on node1, three kubectl binaries in /opt/ch30, and a
# Namespace with a web Service and a client Pod.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

require_snapshot "$LAB_SNAPSHOT"
[[ "$(hostname)" == cp1 ]] || die "run this lab on cp1 (envs/vagrant/kbook-vm ssh)"
require_lab_cluster
if manifests_changed; then
  die "the control plane already runs with --profiling=false (Task 2). To start over, restore the snapshot on the host: envs/vagrant/kbook-vm restore ${LAB_SNAPSHOT}"
fi
for node in node1 node2; do
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$node" true || die "cannot ssh to ${node} from cp1"
done
mkdir -p "$STATE"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# kube-bench on cp1 and node2, checked against the release's checksums; its
# benchmark definitions go to /etc/kube-bench/cfg, where it looks by default.
kb="kube-bench_${KUBE_BENCH_VERSION#v}_linux_amd64.tar.gz"
install_kb='sudo tar -xzf /tmp/ch30-kb.tar.gz -C /tmp/ch30-kb && sudo install -m 0755 /tmp/ch30-kb/kube-bench /usr/local/bin/kube-bench && sudo rm -rf /etc/kube-bench && sudo mkdir -p /etc/kube-bench && sudo cp -r /tmp/ch30-kb/cfg /etc/kube-bench/ && sudo rm -rf /tmp/ch30-kb /tmp/ch30-kb.tar.gz'
if [[ "$(kube-bench version 2>/dev/null)" != "${KUBE_BENCH_VERSION#v}" ||
      "$(ssh node2 'kube-bench version 2>/dev/null')" != "${KUBE_BENCH_VERSION#v}" ]]; then
  info "Installing kube-bench ${KUBE_BENCH_VERSION} on cp1 and node2"
  base="https://github.com/aquasecurity/kube-bench/releases/download/${KUBE_BENCH_VERSION}"
  curl -fsSL "${base}/${kb}" -o "${tmp}/${kb}"
  curl -fsSL "${base}/kube-bench_${KUBE_BENCH_VERSION#v}_checksums.txt" -o "${tmp}/checksums.txt"
  (cd "$tmp" && grep " ${kb}$" checksums.txt | sha256sum -c --quiet -) || die "checksum mismatch for ${kb}"
  cp "${tmp}/${kb}" /tmp/ch30-kb.tar.gz && mkdir -p /tmp/ch30-kb && bash -c "$install_kb"
  scp -q "${tmp}/${kb}" node2:/tmp/ch30-kb.tar.gz
  ssh node2 "mkdir -p /tmp/ch30-kb && ${install_kb}"
fi

# Task 1: node2's kubelet files as kubeadm leaves them (644).
ssh node2 "sudo chmod 644 /lib/systemd/system/kubelet.service /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf ${KUBELET_CONFIG}"

# Task 3: node1's kubelet accepts anonymous requests, allows everything, and
# serves the read-only port.
ssh node1 "sudo sed -i -e '/^  anonymous:/{n;s/enabled: false/enabled: true/}' -e '/^authorization:/{n;s/mode: Webhook/mode: AlwaysAllow/}' -e '/^readOnlyPort:/d' ${KUBELET_CONFIG} &&
  echo 'readOnlyPort: 10255' | sudo tee -a ${KUBELET_CONFIG} >/dev/null && sudo systemctl restart kubelet"
readonly_port_open() { curl -s -m 2 -o /dev/null http://node1:10255/healthz; }
wait_for "node1's read-only port" 120 readonly_port_open
wait_for "node1 Ready" 180 node_ready node1

# Task 4: three binaries, in a random order: the genuine kubectl, a copy with one
# extra byte, and the previous release's kubectl.
info "Downloading kubectl ${K8S_VERSION} and ${K8S_PREV_VERSION}"
dl="https://dl.k8s.io/release"
curl -fsSL "${dl}/${K8S_VERSION}/bin/linux/amd64/kubectl" -o "${tmp}/genuine"
curl -fsSL "${dl}/${K8S_VERSION}/bin/linux/amd64/kubectl.sha512" -o "${tmp}/genuine.sha512"
echo "$(cat "${tmp}/genuine.sha512")  ${tmp}/genuine" | sha512sum --check --quiet || die "the downloaded kubectl ${K8S_VERSION} does not match its checksum"
curl -fsSL "${dl}/${K8S_PREV_VERSION}/bin/linux/amd64/kubectl" -o "${tmp}/older"
cp "${tmp}/genuine" "${tmp}/tampered" && printf '\n' >> "${tmp}/tampered"
mapfile -t names < <(printf '%s\n' a b c | shuf)
sudo rm -rf "$BIN_DIR" && sudo mkdir -p "$BIN_DIR"
sudo install -m 0755 "${tmp}/genuine" "${BIN_DIR}/kubectl-${names[0]}"
sudo install -m 0755 "${tmp}/tampered" "${BIN_DIR}/kubectl-${names[1]}"
sudo install -m 0755 "${tmp}/older" "${BIN_DIR}/kubectl-${names[2]}"
printf 'kubectl-%s\n' "${names[0]}" > "${STATE}/genuine"
cat "${tmp}/genuine.sha512" > "${STATE}/genuine.sha512"

# Task 5: a web Service and a client in a fresh Namespace.
lab_teardown_ns "$LAB_NS"
lab_create_ns "$LAB_NS"
kubectl -n "$LAB_NS" create deployment web --image=nginx:1.27 >/dev/null
kubectl -n "$LAB_NS" expose deployment web --port=80 >/dev/null
kubectl -n "$LAB_NS" run client --image=busybox:1.36 -- sleep infinity >/dev/null
kubectl -n "$LAB_NS" rollout status deployment/web --timeout=180s >/dev/null
wait_for "pod client Running" 180 pod_phase_is "$LAB_NS" client Running

info "Lab ready: kube-bench ${KUBE_BENCH_VERSION} on cp1 and node2, three binaries in ${BIN_DIR}. Namespace: ${LAB_NS}"
