#!/usr/bin/env bash
# Tier 2: the starting state is the cluster snapshot plus, on node1, a service
# nobody needs, a user with too much sudo, and an AppArmor profile that is not
# loaded; on node2, a Pod that runs without seccomp.
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
for node in node1 node2; do
  on "$node" true || die "cannot ssh to ${node} from cp1"
done

# A clean start: the Namespace, the answer file, and the nodes.
lab_teardown_ns "$LAB_NS"
rm -f "$SERVICE_FILE"
clean_nodes
mkdir -p "$STATE"
lab_create_ns "$LAB_NS"

# Task 1: a web server nobody needs, under a name chosen for this run.
service="${SERVICE_NAMES[RANDOM % ${#SERVICE_NAMES[@]}]}"
printf '%s\n' "$service" > "${STATE}/service"
# shellcheck disable=SC2029  # service and port expand here, on cp1
on node1 "sudo tee /etc/systemd/system/${service}.service >/dev/null <<UNIT
[Unit]
Description=Shares /usr/share/doc over HTTP
After=network-online.target

[Service]
ExecStart=/usr/bin/python3 -m http.server ${LEGACY_PORT} --directory /usr/share/doc
DynamicUser=yes
Restart=always

[Install]
WantedBy=multi-user.target
UNIT
  sudo systemctl daemon-reload
  sudo systemctl enable --now ${service} >/dev/null 2>&1" || die "could not start the service on node1"
listening() { [[ -n "$(on node1 "sudo ss -Htln 'sport = :${LEGACY_PORT}'")" ]]; }
wait_for "a listener on node1:${LEGACY_PORT}" 60 listening

# Task 2: user ops, in the sudo group and with a sudoers rule of its own.
on node1 "sudo useradd -m -s /bin/bash -G sudo ops
  echo 'ops ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/ops >/dev/null
  sudo chmod 0440 /etc/sudoers.d/ops
  sudo visudo -cq" || die "could not create user ops on node1"

# Task 3: the AppArmor profile, on disk but not loaded.
scp -q -o BatchMode=yes "${MANIFESTS}/${APPARMOR_PROFILE}" "node1:/tmp/${APPARMOR_PROFILE}"
# shellcheck disable=SC2029
on node1 "sudo install -m 0644 /tmp/${APPARMOR_PROFILE} /etc/apparmor.d/${APPARMOR_PROFILE} && rm -f /tmp/${APPARMOR_PROFILE}"

# Task 5: a Pod on node2 that sets no seccomp profile.
kubectl -n "$LAB_NS" apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: plain
spec:
  nodeSelector:
    kubernetes.io/hostname: node2
  containers:
    - name: plain
      image: busybox:1.36
      command: ["sleep", "infinity"]
      resources:
        requests:
          cpu: 10m
          memory: 16Mi
        limits:
          memory: 32Mi
YAML
wait_for "pod plain Running" 180 pod_phase_is "$LAB_NS" plain Running
info "Lab ready. Namespace: ${LAB_NS}; work on node1 and node2 with ssh from cp1."
