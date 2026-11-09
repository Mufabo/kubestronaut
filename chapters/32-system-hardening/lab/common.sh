# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # variables come from the sourcing script and lab.env
# Shared by setup, verify, solve, and teardown. Sourced after lib.sh and lab.env.

STATE="${here}/.state"
MANIFESTS="${here}/../manifests"
# The services Task 1 may plant; setup picks one per run.
SERVICE_NAMES=(legacy-share report-viewer print-portal doc-mirror)
SECCOMP_DIR=/var/lib/kubelet/seccomp

# on <node> <command>: run a command on a worker over the lab's SSH key.
on() {
  local node=$1; shift
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$node" "$@"
}

# The service Task 1 planted in this run.
planted_service() { cat "${STATE}/service" 2>/dev/null; }

# Remove everything the lab puts on the workers, and undo the reader's changes
# that outlast it: the planted service, user ops, the AppArmor profile, the
# seccomp profile, and seccompDefault on node2's kubelet.
clean_nodes() {
  local names="${SERVICE_NAMES[*]}"
  # shellcheck disable=SC2029  # the names expand here, on cp1
  on node1 "for s in ${names}; do
      sudo systemctl disable --now \"\$s\" >/dev/null 2>&1 || true
      sudo systemctl unmask \"\$s\" >/dev/null 2>&1 || true
      sudo rm -f \"/etc/systemd/system/\$s.service\"
    done
    sudo systemctl daemon-reload
    sudo rm -f /etc/sudoers.d/ops
    if id ops >/dev/null 2>&1; then sudo userdel -r ops >/dev/null 2>&1; fi
    if sudo grep -q '^${APPARMOR_PROFILE} ' /sys/kernel/security/apparmor/profiles; then
      sudo apparmor_parser -R /etc/apparmor.d/${APPARMOR_PROFILE} >/dev/null 2>&1 ||
        echo -n '${APPARMOR_PROFILE}' | sudo tee /sys/kernel/security/apparmor/.remove >/dev/null
    fi
    sudo rm -f /etc/apparmor.d/${APPARMOR_PROFILE} ${SECCOMP_DIR}/${SECCOMP_PROFILE}" ||
    die "could not clean node1"
  if on node2 "sudo grep -q '^seccompDefault: *true' /var/lib/kubelet/config.yaml ||
               sudo grep -q -- '--seccomp-default' /var/lib/kubelet/kubeadm-flags.env"; then
    info "Turning seccompDefault off again on node2"
    on node2 "sudo sed -i '/^seccompDefault:/d' /var/lib/kubelet/config.yaml
      sudo sed -i 's/ *--seccomp-default\(=[a-z]*\)\?//' /var/lib/kubelet/kubeadm-flags.env
      sudo systemctl restart kubelet" || die "could not reset the kubelet on node2"
    wait_for "node2 Ready" 180 node_ready node2
  fi
}

node_ready() {
  [[ "$(kubectl get node "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == True ]]
}
