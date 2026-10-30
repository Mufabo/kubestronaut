# shellcheck shell=bash
# Shared by setup and teardown. Sourced after lib.sh and lab.env.

# remove_controller: the Helm release from Task 6, its Namespace, and what
# `helm uninstall` leaves behind (Traefik's CRDs). Safe when nothing is installed.
remove_controller() {
  local crds
  if command -v helm >/dev/null 2>&1; then
    helm uninstall "$CONTROLLER_RELEASE" -n "$CONTROLLER_NS" --wait >/dev/null 2>&1 || true
  fi
  kubectl delete namespace "$CONTROLLER_NS" --ignore-not-found --wait=true --timeout=180s >/dev/null
  kubectl delete ingressclass traefik --ignore-not-found >/dev/null
  crds="$(kubectl get crd -o name 2>/dev/null | grep -E '\.traefik\.io$' || true)"
  if [[ -n "$crds" ]]; then
    # shellcheck disable=SC2086  # one CRD name per word
    kubectl delete $crds --ignore-not-found >/dev/null
  fi
}
