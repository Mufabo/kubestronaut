#!/usr/bin/env bash
# Print a normalized snapshot of the resources in the given namespaces.
#   snapshot-state.sh <namespace>...
# Used by tools/test-lab.sh to prove that verify.sh is read-only.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
types="pods,services,configmaps,secrets,serviceaccounts,persistentvolumeclaims,roles.rbac.authorization.k8s.io,rolebindings.rbac.authorization.k8s.io,deployments.apps,replicasets.apps,daemonsets.apps,statefulsets.apps,jobs.batch,cronjobs.batch,ingresses.networking.k8s.io,networkpolicies.networking.k8s.io"
for ns in "$@"; do
  echo "## namespace ${ns}"
  kubectl -n "$ns" get "$types" -o json | python3 "${here}/snapshot-normalize.py"
done
