#!/usr/bin/env bash
# Stage "cluster-join", workers only: join the cluster cp1 just created. The
# driver runs this after cluster-init has finished, so the join command exists.
set -euo pipefail
JOIN=/vagrant/.state/join.sh
[[ -s "$JOIN" ]] || { echo "no join command at ${JOIN}; run cluster-init on cp1 first" >&2; exit 1; }
if [[ ! -f /etc/kubernetes/kubelet.conf ]]; then
  bash "$JOIN"
fi
