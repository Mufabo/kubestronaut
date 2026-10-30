#!/usr/bin/env bash
# Stage "cluster-init", cp1 only: kubeadm init, the pinned Calico CNI, the
# reader's kubeconfig (context kbook-vm), the lab-cluster marker, and a join
# command the workers read from the shared state folder. Runs as root.
set -euo pipefail
STATE=/vagrant/.state
POD_CIDR=10.244.0.0/16   # must not overlap the VMs' own 192.168.56.0/24
mkdir -p "$STATE"
# A join command from an earlier build would point the workers at a cluster
# that no longer exists.
rm -f "$STATE/join.sh"

# kubeadm wants two CPUs on a control plane node. The lab VMs have one by
# default (see the Vagrantfile), which is slower but works; skip only that check.
preflight=()
(($(nproc) < 2)) && preflight=(--ignore-preflight-errors=NumCPU)
if [[ ! -f /etc/kubernetes/admin.conf ]]; then
  kubeadm init \
    --apiserver-advertise-address="$NODE_IP" \
    --pod-network-cidr="$POD_CIDR" \
    --kubernetes-version="$K8S_VERSION" \
    "${preflight[@]}"
fi
export KUBECONFIG=/etc/kubernetes/admin.conf

# Calico's manifest defaults to 192.168.0.0/16, which contains the VM network.
# Point its IP pool at POD_CIDR instead.
curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml" |
  sed -e 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' \
      -e "s|#   value: \"192.168.0.0/16\"|  value: \"${POD_CIDR}\"|" |
  kubectl apply -f - >/dev/null
kubectl -n kube-system rollout status daemonset/calico-node --timeout=600s

# The reader's kubeconfig: the admin credentials, under the context name the
# Tier 2 labs expect (LAB_CONTEXT=kbook-vm).
mkdir -p /home/vagrant/.kube
cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
kubectl --kubeconfig /home/vagrant/.kube/config config rename-context \
  "$(kubectl --kubeconfig /home/vagrant/.kube/config config current-context)" kbook-vm >/dev/null
chown -R vagrant:vagrant /home/vagrant/.kube

# The marker tools/lib.sh checks before any lab may change anything
# (LAB_CLUSTER_NAME=kbook-vm in Tier 2 labs).
kubectl apply -f - >/dev/null <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: kbook-lab-marker
  namespace: kube-system
  labels:
    kubestronaut.io/environment: lab
data:
  cluster: kbook-vm
YAML

kubeadm token create --print-join-command > "$STATE/join.sh"
chmod 600 "$STATE/join.sh"
