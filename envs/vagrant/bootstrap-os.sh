#!/usr/bin/env bash
# Stage "os", every node: what any Kubernetes node needs before the Kubernetes
# packages: working DNS, swap off, kernel modules and sysctls, containerd, host
# names for the other VMs, and SSH from cp1 to the workers. Runs as root.
# The driver snapshots the result as `os`, the root of every other snapshot.
set -euo pipefail
STATE=/vagrant/.state
mkdir -p "$STATE"

# Name resolution first: on the VirtualBox NAT network, systemd-resolved's DNSSEC
# validation rejects valid answers ("missing-key"), so package downloads fail. The
# lab VMs turn it off; the drop-in survives reboots.
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/kbook-lab.conf <<RESOLVED
[Resolve]
DNSSEC=no
RESOLVED
systemctl restart systemd-resolved

# The other VMs by name, as on the exam's SSH hosts.
sed -i '/# kbook-lab$/d' /etc/hosts
while read -r line; do
  [[ -n "$line" ]] && echo "${line} # kbook-lab" >> /etc/hosts
done <<<"$HOSTS"

# Kubernetes needs swap off, two kernel modules, and bridged traffic through iptables.
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

# containerd with the systemd cgroup driver, which the kubelet expects, plus the
# tools the labs use on the nodes.
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq containerd apt-transport-https ca-certificates curl gpg make python3
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# SSH between the VMs as the vagrant user: cp1 makes the lab key (once per
# build), every node trusts it, and cp1 can `ssh node1` without a password.
# The key only opens these throwaway VMs; it lives in the git-ignored state folder.
if [[ "$NODE_NAME" == cp1 ]]; then
  rm -f "$STATE/id_ed25519" "$STATE/id_ed25519.pub"
  ssh-keygen -q -t ed25519 -N "" -C "kbook-lab" -f "$STATE/id_ed25519"
  install -m 600 -o vagrant -g vagrant "$STATE/id_ed25519" /home/vagrant/.ssh/id_ed25519
  install -m 644 -o vagrant -g vagrant "$STATE/id_ed25519.pub" /home/vagrant/.ssh/id_ed25519.pub
  cat > /home/vagrant/.ssh/config <<SSHCONFIG
Host node1 node2 cp1
  StrictHostKeyChecking accept-new
  UserKnownHostsFile /home/vagrant/.ssh/known_hosts
SSHCONFIG
  chown vagrant:vagrant /home/vagrant/.ssh/config
  chmod 600 /home/vagrant/.ssh/config
fi
for _ in $(seq 1 60); do
  [[ -s "$STATE/id_ed25519.pub" ]] && break
  sleep 2
done
[[ -s "$STATE/id_ed25519.pub" ]] || { echo "no lab SSH key from cp1" >&2; exit 1; }
sed -i '/ kbook-lab$/d' /home/vagrant/.ssh/authorized_keys
cat "$STATE/id_ed25519.pub" >> /home/vagrant/.ssh/authorized_keys
