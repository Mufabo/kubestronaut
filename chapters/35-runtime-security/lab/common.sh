# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # variables come from the sourcing script and lab.env
# Shared by setup, verify, solve, and teardown. Sourced after lib.sh and lab.env.

STATE="${here}/.state"
# The Deployments of Task 2; setup picks the one that misbehaves.
SUSPECTS=(inventory billing search)
FALCO_UNIT=falco-modern-bpf

# on <node> <command>: run a command on a worker over the lab's SSH key.
on() {
  local node=$1; shift
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$node" "$@"
}

# The API server runs with an audit policy (Task 1).
apiserver_audits() {
  sudo grep -q -- '--audit-policy-file' "$APISERVER_MANIFEST"
}

# The running API server's command line, one flag per line.
apiserver_flags() {
  local pid
  pid="$(pgrep -f 'kube-apiserver --' | head -1)"
  [[ -n "$pid" ]] && tr '\0' '\n' < "/proc/${pid}/cmdline"
}

# Falco at FALCO_VERSION on node1, with the modern eBPF probe, and without
# falcoctl's automatic rule updates, so the rules stay those of the release.
install_falco() {
  if [[ "$(on node1 'falco --version 2>/dev/null | grep -m1 "^Falco version"')" == "Falco version: ${FALCO_VERSION}" ]]; then
    return 0
  fi
  info "Installing Falco ${FALCO_VERSION} on node1"
  # shellcheck disable=SC2029  # FALCO_VERSION expands here, on cp1
  on node1 "set -euo pipefail
    curl -fsSL https://falco.org/repo/falcosecurity-packages.asc |
      sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/falco-archive-keyring.gpg
    echo 'deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] https://download.falco.org/packages/deb stable main' |
      sudo tee /etc/apt/sources.list.d/falcosecurity.list >/dev/null
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive FALCO_FRONTEND=noninteractive FALCO_DRIVER_CHOICE=modern_ebpf \
      apt-get install -y -qq falco=${FALCO_VERSION} >/dev/null
    sudo systemctl disable --now falcoctl-artifact-follow >/dev/null 2>&1 || true
    sudo systemctl mask falcoctl-artifact-follow >/dev/null 2>&1" || die "could not install Falco on node1"
}

falco_running() { on node1 "systemctl is-active --quiet ${FALCO_UNIT}"; }
