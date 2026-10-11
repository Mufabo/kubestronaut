#!/usr/bin/env bash
# Workers: wait for the control plane's join command, then join once.
set -euo pipefail
JOIN=/vagrant/envs/vagrant/.state/join.sh
for _ in $(seq 1 120); do
  [[ -s "$JOIN" ]] && break
  sleep 5
done
[[ -s "$JOIN" ]] || { echo "no join command after 10 minutes" >&2; exit 1; }
if [[ ! -f /etc/kubernetes/kubelet.conf ]]; then
  bash "$JOIN"
fi
