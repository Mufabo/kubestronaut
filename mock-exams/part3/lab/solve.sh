#!/usr/bin/env bash
# Reference solution for the Part III simulator (used to test the exam on cp1).
# Human-readable version: solutions.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_snapshot "$LAB_SNAPSHOT"
require_lab_cluster
C=$COURSE

# Q15 first: with node2 back, everything later has two workers.
on node2 "sudo sed -i 's|^ExecStart=/usr/local/bin/kubelet |ExecStart=/usr/bin/kubelet |' ${DROPIN} && sudo systemctl daemon-reload && sudo systemctl enable --now kubelet && sudo systemctl restart kubelet" >/dev/null 2>&1
wait_for "node2 Ready" 300 node_ready node2

# Q4: upgrade the control plane node (Chapter 19), retrying through API server restarts.
prev_minor="$(cut -d. -f1-2 <<<"$K8S_PREV_VERSION")"
minor="$(cut -d. -f1-2 <<<"$K8S_VERSION")"
upgrade_packages() {
  local pkgs="$*" args="" p
  for p in "$@"; do args+=" ${p}=\$v"; done
  bash -c "set -e
    sudo sed -i 's|/${prev_minor}/|/${minor}/|' /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update -qq
    v=\$(apt-cache madison kubeadm | awk '{print \$3}' | grep '^${K8S_VERSION#v}-' | head -1)
    sudo apt-mark unhold ${pkgs} >/dev/null
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o Dpkg::Options::=--force-confold ${args} >/dev/null
    sudo apt-mark hold ${pkgs} >/dev/null"
}
api_stable() {
  local since
  kubectl get --raw /readyz >/dev/null 2>&1 &&
  since="$(kubectl -n kube-system get pod kube-apiserver-cp1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)" &&
  [[ -n "$since" ]] && (($(date +%s) - $(date -d "$since" +%s) >= 30))
}
drain_cp1() { kubectl drain cp1 --ignore-daemonsets --delete-emptydir-data --timeout=300s >/dev/null 2>&1; }
uncordon_cp1() { kubectl uncordon cp1 >/dev/null 2>&1; }
cp1_at_target() { [[ "$(kubectl get node cp1 -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)" == "$K8S_VERSION" ]]; }
upgrade_packages kubeadm
# Its preflight runs a health-check Job that must finish in 15 seconds, which a
# busy one-CPU node can miss. It fails before changing anything, so retry it.
upgrade_apply_once() { sudo kubeadm upgrade apply -y "$K8S_VERSION" >/dev/null 2>&1; }
wait_for "kubeadm upgrade apply ${K8S_VERSION}" 1800 upgrade_apply_once
wait_for "cp1 drained" 600 drain_cp1
upgrade_packages kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
wait_for "cp1 reports ${K8S_VERSION}" 300 cp1_at_target
wait_for "API server stable after the kubelet restart" 600 api_stable
wait_for "cp1 uncordoned" 300 uncordon_cp1

# Q1
kubectl -n p3-sched apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: fast
spec:
  nodeSelector:
    kubernetes.io/hostname: cp1
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
  containers:
    - name: fast
      image: nginx:1.27
YAML

# Q2
sudo tee /etc/kubernetes/manifests/ops-monitor.yaml >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: ops-monitor
  namespace: p3-ops
spec:
  containers:
    - name: ops-monitor
      image: busybox:1.36
      command: ["sleep", "infinity"]
YAML

# Q3
sudo kubeadm token create --print-join-command | tee "${C}/3/join.sh" >/dev/null

# Q5
kubectl -n p3-apps set image deployment/report report=nginx:1.27 >/dev/null

# Q6
etcdctl_k8s snapshot save "${C}/6/etcd.db" >/dev/null 2>&1

# Q7
kubectl -n p3-net apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-allow
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api
      ports:
        - protocol: TCP
          port: 80
YAML

# Q8
sudo grep -oE -- '--service-cluster-ip-range=[^ ]+' /etc/kubernetes/manifests/kube-apiserver.yaml | cut -d= -f2 > "${C}/8/service-cidr.txt"

# Q9
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: logs-pv
spec:
  capacity:
    storage: 1Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /srv/p3-logs
    type: DirectoryOrCreate
YAML
kubectl -n p3-data apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: logs
spec:
  storageClassName: manual
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 500Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: writer
spec:
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh", "-c", "date > /logs/started; sleep infinity"]
      volumeMounts:
        - name: logs
          mountPath: /logs
  volumes:
    - name: logs
      persistentVolumeClaim:
        claimName: logs
YAML

# Q10
kubectl -n p3-apps create serviceaccount deployer >/dev/null
kubectl -n p3-apps create role deploy-manager --verb=get,list,create,update --resource=deployments.apps >/dev/null
kubectl -n p3-apps create rolebinding deployer --role=deploy-manager --serviceaccount=p3-apps:deployer >/dev/null

# Q11
kubectl create clusterrole node-reader --verb=get,list --resource=nodes >/dev/null
kubectl create clusterrolebinding auditor-nodes --clusterrole=node-reader --user=auditor >/dev/null

# Q12
kubectl -n p3-ops apply -f - >/dev/null <<'YAML'
apiVersion: ops.kbook.io/v1
kind: Backup
metadata:
  name: nightly
spec:
  schedule: "0 2 * * *"
  retain: 7
YAML

# Q13
kubectl -n p3-apps autoscale deployment web --min=2 --max=5 --cpu=60% >/dev/null

# Q14
kubectl -n p3-apps patch service shop --type=json -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":80}]' >/dev/null

# Q16
sudo openssl x509 -enddate -noout -in /etc/kubernetes/pki/etcd/ca.crt | cut -d= -f2 > "${C}/16/etcd-ca-expiry.txt"

# Wait for what the checks look at.
wait_for "pod fast Running" 300 pod_phase_is p3-sched fast Running
wait_for "static pod ops-monitor-cp1 Running" 300 pod_phase_is p3-ops ops-monitor-cp1 Running
wait_for "pod writer Running" 300 pod_phase_is p3-data writer Running
# Settled means the rollout is done and the old Pod with the broken image is gone,
# not only that a new one is available: verify must find a cluster that holds still.
report_settled() {
  [[ "$(kubectl -n p3-apps get deployment report -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" == 1 ]] &&
  [[ "$(kubectl -n p3-apps get pods -l app=report -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null)" == nginx:1.27 ]]
}
wait_for "report rolled out, old Pod gone" 300 report_settled
# The new kubelet on cp1 recreates the control plane's mirror Pods; wait until
# all three report the new version and are Ready again before anything is scored.
control_plane_settled() {
  local rows
  rows="$(kubectl -n kube-system get pods -l 'component in (kube-apiserver,kube-controller-manager,kube-scheduler)' \
    -o jsonpath='{range .items[*]}{.spec.containers[0].image} {.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null)"
  [[ "$(grep -c ":${K8S_VERSION} True$" <<<"$rows")" == 3 && "$(wc -l <<<"$rows")" == 3 ]] &&
  [[ "$(kubectl get node cp1 -o jsonpath='{.status.nodeInfo.kubeletVersion} {.spec.unschedulable}' 2>/dev/null)" == "${K8S_VERSION} " ]]
}
wait_for "the control plane settled at ${K8S_VERSION}" 600 control_plane_settled
