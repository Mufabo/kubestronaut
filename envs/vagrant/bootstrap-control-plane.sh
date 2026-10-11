#!/usr/bin/env bash
# Control plane only: kubeadm init, the admin kubeconfig for the vagrant user, the
# pinned Calico CNI, and a join command the workers read from the shared folder.
set -euo pipefail
STATE=/vagrant/envs/vagrant/.state
mkdir -p "$STATE"

if [[ ! -f /etc/kubernetes/admin.conf ]]; then
  # 192.168.0.0/16 is Calico's default pool, so it matches the Tier 1 cluster.
  kubeadm init \
    --apiserver-advertise-address="$NODE_IP" \
    --pod-network-cidr=192.168.0.0/16 \
    --kubernetes-version="$K8S_VERSION"
fi

mkdir -p /home/vagrant/.kube
cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml" >/dev/null
kubectl -n kube-system rollout status daemonset/calico-node --timeout=300s

kubeadm token create --print-join-command > "$STATE/join.sh"
chmod 600 "$STATE/join.sh"
