#!/usr/bin/env bash
# Every node: container runtime, kubelet, kubeadm and kubectl at the pinned minor
# version. Runs as root inside the VM. Idempotent enough to re-run with `vagrant provision`.
set -euo pipefail

# Kubernetes needs swap off and two kernel modules and bridged traffic through iptables.
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab
cat > /etc/modules-load.d/k8s.conf <<MODULES
overlay
br_netfilter
MODULES
modprobe overlay
modprobe br_netfilter
cat > /etc/sysctl.d/99-k8s.conf <<SYSCTL
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
SYSCTL
sysctl --system >/dev/null

# containerd with the systemd cgroup driver, which kubelet expects.
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq containerd apt-transport-https ca-certificates curl gpg
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# kubelet, kubeadm and kubectl from the community repository for this minor version.
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# The kubelet uses this node's address on the private network, not the NAT one.
echo "KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}" > /etc/default/kubelet
systemctl enable kubelet
