#!/usr/bin/env bash
# Tier 2: the starting state is the cluster snapshot, gVisor on the workers,
# etcdctl on cp1, and three Namespaces: Pods to judge, a Deployment that the
# restricted level blocks, a Secret, and an empty Namespace for the sandbox.
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
if apiserver_encrypts; then
  die "the API server already encrypts at rest (Task 4). To start over, restore the snapshot on the host: envs/vagrant/kbook-vm restore ${LAB_SNAPSHOT}"
fi
for node in node1 node2; do
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$node" true || die "cannot ssh to ${node} from cp1"
done

# etcdctl and etcdutl (Task 4), as in Chapter 20, checked against the release's checksums.
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

# gVisor on both workers (Task 5): runsc and its shim from the pinned release,
# checked against its SHA512SUMS, and a runsc runtime in containerd.
for node in node1 node2; do
  if [[ "$(ssh "$node" '/usr/local/bin/runsc --version 2>/dev/null | head -1')" == "runsc version ${GVISOR_VERSION}" ]] &&
     ssh "$node" "sudo grep -q 'runtimes.runsc' /etc/containerd/config.toml"; then
    continue
  fi
  info "Installing gVisor ${GVISOR_VERSION} on ${node}"
  # shellcheck disable=SC2029  # GVISOR_VERSION is meant to expand here, on cp1
  ssh "$node" "set -euo pipefail
    tmp=\$(mktemp -d); cd \"\$tmp\"
    base=https://github.com/google/gvisor/releases/download/${GVISOR_VERSION}
    curl -fsSLO \"\$base/gvisor-x86_64.tar.zstd\"
    curl -fsSLO \"\$base/SHA512SUMS\"
    grep ' gvisor-x86_64.tar.zstd\$' SHA512SUMS | sha512sum -c --quiet -
    sudo tar --zstd -xf gvisor-x86_64.tar.zstd -C /usr/local/bin
    if ! sudo grep -q 'runtimes.runsc' /etc/containerd/config.toml; then
      printf '\n[plugins.%s.containerd.runtimes.runsc]\n  runtime_type = %s\n' \"'io.containerd.cri.v1.runtime'\" \"'io.containerd.runsc.v1'\" |
        sudo tee -a /etc/containerd/config.toml >/dev/null
    fi
    sudo systemctl restart containerd
    rm -rf \"\$tmp\"" || die "could not install gVisor on ${node}"
done
node_ready() { [[ "$(kubectl get node "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" == True ]]; }
for node in node1 node2; do wait_for "${node} Ready" 180 node_ready "$node"; done

# A clean start: the lab's Namespaces, the RuntimeClass, and the answer file.
for ns in "${NAMESPACES[@]}"; do lab_teardown_ns "$ns"; done
kubectl delete runtimeclass gvisor --ignore-not-found >/dev/null
rm -f "$VIOLATIONS_FILE"
mkdir -p "$STATE"
for ns in "${NAMESPACES[@]}"; do lab_create_ns "$ns"; done

# Task 1: three Pods that break baseline, and two that do not.
kubectl -n ch33-legacy apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: metrics
spec:
  hostPID: true
  containers:
    - name: metrics
      image: busybox:1.36
      command: ["sleep", "infinity"]
---
apiVersion: v1
kind: Pod
metadata:
  name: debugger
spec:
  containers:
    - name: debugger
      image: busybox:1.36
      command: ["sleep", "infinity"]
      securityContext:
        privileged: true
---
apiVersion: v1
kind: Pod
metadata:
  name: backup
spec:
  volumes:
    - name: host
      hostPath:
        path: /var/log
  containers:
    - name: backup
      image: busybox:1.36
      command: ["sleep", "infinity"]
      volumeMounts:
        - name: host
          mountPath: /host-logs
          readOnly: true
---
apiVersion: v1
kind: Pod
metadata:
  name: web
spec:
  containers:
    - name: web
      image: busybox:1.36
      command: ["sleep", "infinity"]
---
apiVersion: v1
kind: Pod
metadata:
  name: cache
spec:
  containers:
    - name: cache
      image: busybox:1.36
      command: ["sleep", "infinity"]
      securityContext:
        runAsUser: 0
YAML

# Task 2: ch33-apps enforces restricted, so worker's ReplicaSet cannot create Pods.
kubectl label namespace ch33-apps pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null
kubectl -n ch33-apps create deployment worker --image=busybox:1.36 --replicas=2 -- sleep infinity >/dev/null 2>&1

# Tasks 3 and 4: a Secret with a value made up for this run.
password="$(head -c 12 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | cut -c1-12)"
printf '%s\n' "$password" > "${STATE}/db-pass"
kubectl -n ch33-apps create secret generic db-pass --from-literal=password="$password" >/dev/null

for p in metrics debugger backup web cache; do
  wait_for "pod ${p} Running" 180 pod_phase_is ch33-legacy "$p" Running
done
info "Lab ready: gVisor ${GVISOR_VERSION} on node1 and node2, etcdctl ${ETCD_VERSION} on cp1. Namespaces: ${NAMESPACES[*]}"
