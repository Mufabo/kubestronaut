# shellcheck shell=bash
# Shared by setup and teardown. Sourced after lib.sh and lab.env.

metallb_manifest() {
  echo "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"
}

# The last 51 addresses of the kind network's IPv4 /16, which Docker hands out
# from the bottom: 172.18.0.0/16 gives 172.18.255.200-172.18.255.250.
lb_pool_range() {
  local subnet
  subnet="$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' | tr ' ' '\n' | grep -m1 -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/')"
  [[ -n "$subnet" ]] || die "cannot read the IPv4 subnet of the kind Docker network"
  echo "${subnet%.*.*}.255.200-${subnet%.*.*}.255.250"
}

pool_applies() {
  kubectl apply -f - >/dev/null 2>&1 <<YAML
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ${LAB_LB_POOL}
  namespace: metallb-system
spec:
  addresses:
    - $(lb_pool_range)
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: ${LAB_LB_POOL}
  namespace: metallb-system
spec:
  ipAddressPools:
    - ${LAB_LB_POOL}
YAML
}

metallb_ns_settled() {
  [[ "$(kubectl get namespace metallb-system -o jsonpath='{.status.phase}' 2>/dev/null)" != Terminating ]]
}

install_metallb() {
  info "Installing MetalLB ${METALLB_VERSION} with the pool ${LAB_LB_POOL} ($(lb_pool_range))"
  # A teardown just before may still be removing the old install.
  wait_for "the previous metallb-system Namespace to go away" 180 metallb_ns_settled
  kubectl apply -f "$(metallb_manifest)" >/dev/null
  kubectl -n metallb-system rollout status deployment/controller --timeout=180s >/dev/null
  kubectl -n metallb-system rollout status daemonset/speaker --timeout=180s >/dev/null
  # The pool is refused until MetalLB's admission webhook answers.
  wait_for "MetalLB to accept the address pool" 120 pool_applies
}

# Safe when nothing is installed.
remove_metallb() {
  kubectl delete -f "$(metallb_manifest)" --ignore-not-found --wait=true --timeout=180s >/dev/null 2>&1 || true
}
