# shellcheck shell=bash
# Shared by setup and teardown. Sourced after lib.sh and lab.env.

# remove_operator: the Helm release from Task 6, its Namespace, the CRDs the
# chart keeps on uninstall, and any Leases a default install left in kube-system.
remove_operator() {
  local crds
  if command -v helm >/dev/null 2>&1; then
    helm uninstall "$CM_RELEASE" -n "$CM_NS" --wait >/dev/null 2>&1 || true
  fi
  kubectl delete namespace "$CM_NS" --ignore-not-found --wait=true --timeout=180s >/dev/null
  crds="$(kubectl get crd -o name 2>/dev/null | grep -E '\.cert-manager\.io$' || true)"
  if [[ -n "$crds" ]]; then
    # shellcheck disable=SC2086  # one CRD name per word
    kubectl delete $crds --ignore-not-found >/dev/null
  fi
  kubectl -n kube-system delete lease cert-manager-controller cert-manager-cainjector-leader-election --ignore-not-found >/dev/null
}
