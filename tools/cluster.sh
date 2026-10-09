#!/usr/bin/env bash
# Create (or verify) the Tier 1 kind cluster and mark it as a lab cluster.
# Idempotent. Refuses to silently reuse a cluster whose Kubernetes version no
# longer matches versions.env.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/lib.sh"
require_cmd kind kubectl

ctx="kind-${CLUSTER_NAME}"
exists=0
while IFS= read -r c; do
  [[ "$c" == "$CLUSTER_NAME" ]] && exists=1
done < <(kind get clusters 2>/dev/null)

if ((exists)); then
  running="$(kubectl --context "$ctx" get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}')" ||
    die "cluster '${CLUSTER_NAME}' exists but is not reachable through context ${ctx}"
  if [[ "$running" != "$K8S_VERSION" ]]; then
    die "cluster '${CLUSTER_NAME}' runs ${running}, but versions.env pins ${K8S_VERSION}. Rebuild it with: make cluster-recreate"
  fi
  info "cluster ${CLUSTER_NAME} already exists and runs ${running}"
else
  info "creating kind cluster ${CLUSTER_NAME} (${KIND_NODE_IMAGE})"
  kind create cluster --name "$CLUSTER_NAME" --image "$KIND_NODE_IMAGE" --config "${BOOK_ROOT}/envs/kind/cluster.yaml"
fi

# The marker that tools/lib.sh checks before any lab may change anything.
kubectl --context "$ctx" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${LAB_MARKER_NAME}
  namespace: kube-system
  labels:
    kubestronaut.io/environment: lab
data:
  cluster: ${CLUSTER_NAME}
YAML
info "cluster marked as a lab cluster (kube-system/${LAB_MARKER_NAME})"
