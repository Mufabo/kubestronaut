#!/usr/bin/env bash
# Tier 2: the starting state is the cluster snapshot, the etcd client tools, and
# an older backup (taken while the ConfigMap `legacy` existed) to restore later.
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
if [[ "$(etcd_data_hostpath)" != /var/lib/etcd ]]; then
  die "etcd no longer runs from /var/lib/etcd. To start over, restore the snapshot on the host: envs/vagrant/kbook-vm restore ${LAB_SNAPSHOT}"
fi

# etcdctl and etcdutl at the pinned version, checked against the release's checksums.
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

# The reader's answers, and a restore directory left over from an earlier attempt.
sudo rm -f "$NEW_BACKUP" "$OLD_BACKUP" "$REVISION_FILE"
sudo rm -rf "$RESTORE_DIR"
sudo mkdir -p "$BACKUP_DIR"
mkdir -p "${here}/.state"
rm -f "${here}/.state/current-rv"

lab_teardown_ns "$LAB_NS"
lab_create_ns "$LAB_NS"

# The older backup contains `legacy`; after it, `legacy` is replaced by `current`.
kubectl -n "$LAB_NS" create configmap legacy --from-literal=release=1.0 >/dev/null
etcdctl_k8s snapshot save "$OLD_BACKUP" >/dev/null 2>&1 || die "could not save the starting backup to ${OLD_BACKUP}"
kubectl -n "$LAB_NS" delete configmap legacy >/dev/null
kubectl -n "$LAB_NS" create configmap current --from-literal=release=2.0 >/dev/null
# Task 1's backup must be newer than this point: remember etcd's revision of `current`.
kubectl -n "$LAB_NS" get configmap current -o jsonpath='{.metadata.resourceVersion}' > "${here}/.state/current-rv"

info "Lab ready: etcdctl and etcdutl ${ETCD_VERSION} are installed; the older backup is ${OLD_BACKUP}. Namespace: ${LAB_NS}"
