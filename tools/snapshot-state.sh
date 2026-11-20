#!/usr/bin/env bash
# Print a normalized snapshot of the Tier 1 lab state that a verify run must
# not change. Used by tools/test-lab.sh to prove that verify.sh is read-only.
#   snapshot-state.sh <chapter-number|exam> [part]
#
# What is included, all read from lab/lab.env:
#   - the resources in the lab's namespaces (LAB_SNAPSHOT_NS / LAB_NS)
#   - cluster-scoped or extra resource types named in LAB_SNAPSHOT_CLUSTER
#     (for example "ciliumclusterwidenetworkpolicies,gatewayclasses")
#   - with LAB_SNAPSHOT_NODES=1, each kind node's CNI configuration
#     (/etc/cni/net.d) and its routing table without per-Pod routes, for labs
#     that change the nodes
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/lib.sh"
ch="${1:?chapter number}"
part="${2:-}"
dir="$(bash "${here}/lab-path.sh" "$ch")"

namespaces="$(bash "${here}/lab-namespaces.sh" snapshot "$ch" "$part")"
read -r extra nodes < <(bash -c 'source "$1"; printf "%s %s\n" "${LAB_SNAPSHOT_CLUSTER:--}" "${LAB_SNAPSHOT_NODES:-0}"' _ "${dir}/lab/lab.env")

types="pods,services,configmaps,secrets,serviceaccounts,persistentvolumeclaims,roles.rbac.authorization.k8s.io,rolebindings.rbac.authorization.k8s.io,deployments.apps,replicasets.apps,daemonsets.apps,statefulsets.apps,jobs.batch,cronjobs.batch,ingresses.networking.k8s.io,networkpolicies.networking.k8s.io"
for ns in $namespaces; do
  echo "## namespace ${ns}"
  if [[ -n "$(kubectl get namespace "$ns" -o jsonpath='{.metadata.uid}' 2>/dev/null)" ]]; then
    kubectl -n "$ns" get "$types" -o json | python3 "${here}/snapshot-normalize.py"
  else
    echo "(absent)"
  fi
done

if [[ "$extra" != - ]]; then
  echo "## extra types ${extra}"
  kubectl get "$extra" -A -o json | python3 "${here}/snapshot-normalize.py"
fi

if [[ "$nodes" == 1 ]]; then
  for node in $(kind get nodes --name "$CLUSTER_NAME" 2>/dev/null | sort); do
    echo "## node ${node}"
    # Per-Pod host routes (dev veth..., dev lxc...) come and go with Pods, so
    # they are left out; routes between nodes and to subnets are kept.
    docker exec "$node" sh -c 'cd /etc/cni/net.d 2>/dev/null && find . -type f -exec md5sum {} + | sort; ip route show | grep -Ev " dev (veth|lxc)[^ ]* " | sort' 2>/dev/null || true
  done
fi
