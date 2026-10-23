#!/usr/bin/env bash
# Stage "k8s-tools", every node: kubelet, kubeadm and kubectl at exactly
# $K8S_VERSION, held. Runs as root. The driver runs it at K8S_VERSION for the
# `prereqs` and `cluster` snapshots and at K8S_PREV_VERSION for `cluster-prev`.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# The community repository has one apt source per minor version.
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/Release.key" |
  gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq

# Install the exact package version of the pinned release, not the newest patch
# release: a node must not run a kubelet newer than the control plane.
PKG_VERSION="$(apt-cache madison kubeadm | awk '{print $3}' | grep "^${K8S_VERSION#v}-" | head -1)"
[[ -n "$PKG_VERSION" ]] || { echo "no kubeadm package for ${K8S_VERSION}" >&2; exit 1; }
apt-mark unhold kubelet kubeadm kubectl >/dev/null 2>&1 || true
apt-get install -y -qq --allow-downgrades \
  "kubelet=${PKG_VERSION}" "kubeadm=${PKG_VERSION}" "kubectl=${PKG_VERSION}"
apt-mark hold kubelet kubeadm kubectl >/dev/null

# crictl talks to the container runtime directly (Chapters 20 and 27). Since
# Kubernetes 1.37 the kubeadm package no longer pulls cri-tools in, so install the
# version from the same minor-version repository, and point it at containerd.
apt-get install -y -qq cri-tools
cat > /etc/crictl.yaml <<'YAML'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
YAML

# The kubelet uses this node's address on the private network, not the NAT one.
echo "KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}" > /etc/default/kubelet
systemctl enable kubelet
