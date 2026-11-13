# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # variables come from the sourcing script and lab.env
# Shared names and helpers for the CKS simulator. Sourced by the lab scripts.

STATE="${here}/.state"
MANIFESTS="${here}/../manifests"
NAMESPACES=(cks-shop cks-ci cks-sys cks-pci cks-sbx cks-prod cks-run)
CTX_A=cks-a
CTX_B=cks-b
# Question 5: the profile file on node2, and the name of the profile inside it.
AA_FILE=/etc/apparmor.d/cks-guard
AA_PROFILE=cks-readonly
# Question 6: where the seccomp profile belongs on node1.
SECCOMP_DIR=/var/lib/kubelet/seccomp/cks
# Question 14: the Pods Falco watches; setup picks the one that misbehaves.
SUSPECTS=(cks-run/reporter cks-run/indexer cks-prod/fetcher cks-prod/mailer)
FALCO_UNIT=falco-modern-bpf

base_context() { printf '%s' "$LAB_CONTEXT"; }

# ctx_field <context> <field>   a field of a context from the kubeconfig
ctx_field() { kubectl config view -o "jsonpath={.contexts[?(@.name==\"$1\")].context.$2}"; }

leave_exam_contexts() {
  local cur
  cur="$(kubectl config current-context 2>/dev/null || true)"
  if [[ "$cur" == "$CTX_A" || "$cur" == "$CTX_B" ]]; then
    kubectl config use-context "$(base_context)" >/dev/null
  fi
}

# on <node> <command>: run a command on a worker over the lab's SSH key.
on() {
  local node=$1; shift
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$node" "$@"
}

node_ready() {
  [[ "$(kubectl get node "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == True ]]
}

# The running API server's command line, one flag per line.
apiserver_flags() {
  local pid
  pid="$(pgrep -f 'kube-apiserver --' | head -1)"
  [[ -n "$pid" ]] && tr '\0' '\n' < "/proc/${pid}/cmdline"
}

# apiserver_restarted_with <flag>: the running API server has the flag and is ready.
apiserver_restarted_with() {
  apiserver_flags | grep -qxF -- "$1" && kubectl get --raw /readyz >/dev/null 2>&1
}

# etcdctl against the cluster's etcd, with the client certificate kubeadm created.
etcdctl_k8s() {
  sudo etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key "$@"
}

# etcd_prefix <key>   the first 30 bytes of the value etcd stores under <key>
etcd_prefix() {
  local json value
  json="$(etcdctl_k8s get "$1" -w json 2>/dev/null)" || return 1
  value="$(sed -n 's/.*"value":"\([^"]*\)".*/\1/p' <<<"$json")"
  [[ -n "$value" ]] || return 1
  value="$(base64 -d <<<"$value" 2>/dev/null | tr -d '\0' | cut -c1-30)"
  printf '%s' "${value%%$'\n'*}"
}

# etcdctl and etcdutl, as in Chapter 20, checked against the release's checksums.
install_etcdctl() {
  [[ "$(etcdutl version 2>/dev/null | head -1)" == "etcdutl version: ${ETCD_VERSION#v}" ]] && return 0
  info "Installing etcdctl and etcdutl ${ETCD_VERSION}"
  local tmp base tarball
  tmp="$(mktemp -d)"
  base="https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}"
  tarball="etcd-${ETCD_VERSION}-linux-amd64.tar.gz"
  curl -fsSL "${base}/${tarball}" -o "${tmp}/${tarball}"
  curl -fsSL "${base}/SHA256SUMS" -o "${tmp}/SHA256SUMS"
  (cd "$tmp" && grep " ${tarball}$" SHA256SUMS | sha256sum -c --quiet -) || die "checksum mismatch for ${tarball}"
  tar -xzf "${tmp}/${tarball}" -C "$tmp"
  sudo install -m 0755 "${tmp}/etcd-${ETCD_VERSION}-linux-amd64/etcdctl" "${tmp}/etcd-${ETCD_VERSION}-linux-amd64/etcdutl" /usr/local/bin/
  rm -rf "$tmp"
}

# gVisor on both workers, as in Chapter 33: runsc and its shim from the pinned
# release, checked against its SHA512SUMS, and a runsc runtime in containerd.
install_gvisor() {
  local node
  for node in node1 node2; do
    if [[ "$(on "$node" '/usr/local/bin/runsc --version 2>/dev/null | head -1')" == "runsc version ${GVISOR_VERSION}" ]] &&
       on "$node" "sudo grep -q 'runtimes.runsc' /etc/containerd/config.toml"; then
      continue
    fi
    info "Installing gVisor ${GVISOR_VERSION} on ${node}"
    # shellcheck disable=SC2029  # GVISOR_VERSION is meant to expand here, on cp1
    on "$node" "set -euo pipefail
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
    wait_for "${node} Ready" 180 node_ready "$node"
  done
}

# Falco on node1, as in Chapter 35, without falcoctl's automatic rule updates.
install_falco() {
  if [[ "$(on node1 'falco --version 2>/dev/null | grep -m1 "^Falco version"')" != "Falco version: ${FALCO_VERSION}" ]]; then
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
  fi
  on node1 "sudo systemctl enable --now ${FALCO_UNIT} >/dev/null 2>&1"
}

# Everything the exam creates, or asks the reader to create, outside its
# namespaces, except the API server's changes (questions 4, 8, and 13), which
# only a snapshot restore takes back.
remove_exam() {
  leave_exam_contexts
  lab_delete_contexts "$CTX_A" "$CTX_B"
  info "Removing namespaces ${NAMESPACES[*]} and the exam's cluster-wide objects (if present)"
  kubectl delete namespace "${NAMESPACES[@]}" --ignore-not-found --wait=true --timeout=300s >/dev/null
  kubectl delete validatingadmissionpolicybinding cks-no-latest --ignore-not-found >/dev/null
  kubectl delete validatingadmissionpolicy cks-no-latest --ignore-not-found >/dev/null
  kubectl delete runtimeclass sandboxed --ignore-not-found >/dev/null
  kubectl delete clusterrolebinding deployer-admin --ignore-not-found >/dev/null
  # shellcheck disable=SC2029  # the names expand here, on cp1
  on node2 "if sudo grep -q '^${AA_PROFILE} ' /sys/kernel/security/apparmor/profiles; then
      echo -n '${AA_PROFILE}' | sudo tee /sys/kernel/security/apparmor/.remove >/dev/null
    fi
    sudo rm -f ${AA_FILE}" || die "could not clean node2"
  # shellcheck disable=SC2029
  on node1 "sudo rm -rf ${SECCOMP_DIR}" || die "could not clean node1"
  if course_dir_ok "$COURSE"; then sudo rm -rf "$COURSE"; fi
  rm -f "${STATE}/start" "${STATE}/genuine" "${STATE}/digest" "${STATE}/culprit" "${STATE}/card-key"
}
