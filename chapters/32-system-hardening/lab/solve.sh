#!/usr/bin/env bash
# Automated reference solution (used by the test loop on cp1). Human-readable
# version: solutions.md
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

# Task 1: the listener's process names its unit.
# shellcheck disable=SC2029
pid="$(on node1 "sudo ss -Htlnp 'sport = :${LEGACY_PORT}'" | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | head -1)"
# shellcheck disable=SC2029
unit="$(on node1 "ps -o unit= -p ${pid}" | tr -d ' ')"
# shellcheck disable=SC2029
on node1 "sudo systemctl disable --now ${unit}" >/dev/null 2>&1
printf '%s\n' "$unit" > "$SERVICE_FILE"

# Task 2: the sudoers rule and the sudo group.
on node1 "sudo rm /etc/sudoers.d/ops && sudo gpasswd -d ops sudo" >/dev/null

# Task 3: load the profile, then run the Pod under it.
# shellcheck disable=SC2029
on node1 "sudo apparmor_parser -q /etc/apparmor.d/${APPARMOR_PROFILE}"
kubectl -n "$LAB_NS" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: guarded
spec:
  nodeSelector:
    kubernetes.io/hostname: node1
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: ${APPARMOR_PROFILE}
  containers:
    - name: guarded
      image: busybox:1.36
      command: ["sleep", "infinity"]
YAML

# Task 4: copy the profile to node1's kubelet, then run the Pod with it.
scp -q -o BatchMode=yes "${MANIFESTS}/no-chmod.json" node1:/tmp/no-chmod.json
# shellcheck disable=SC2029
on node1 "sudo install -D -m 0644 /tmp/no-chmod.json ${SECCOMP_DIR}/${SECCOMP_PROFILE} && rm /tmp/no-chmod.json"
kubectl -n "$LAB_NS" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: locked
spec:
  nodeSelector:
    kubernetes.io/hostname: node1
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: ${SECCOMP_PROFILE}
  containers:
    - name: locked
      image: busybox:1.36
      command: ["sleep", "infinity"]
YAML

# Task 5: seccompDefault in node2's kubelet configuration, then a new Pod.
on node2 "cfg=/var/lib/kubelet/config.yaml
  if sudo grep -q '^seccompDefault:' \"\$cfg\"; then
    sudo sed -i 's/^seccompDefault:.*/seccompDefault: true/' \"\$cfg\"
  else
    echo 'seccompDefault: true' | sudo tee -a \"\$cfg\" >/dev/null
  fi
  sudo systemctl restart kubelet"
kubelet_back() { on node2 "systemctl is-active --quiet kubelet" && node_ready node2; }
wait_for "the kubelet on node2" 180 kubelet_back
pod="$(kubectl -n "$LAB_NS" get pod plain -o json)"
kubectl replace --force -f - <<<"$pod" >/dev/null

kubectl -n "$LAB_NS" wait --for=condition=Ready pod/guarded pod/locked pod/plain --timeout=180s >/dev/null
