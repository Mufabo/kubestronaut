# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2153,SC2329  # variables come from lab.env; functions are passed to wait_for by name
# Shared helpers for the Chapter 18 lab parts. Sourced by the dispatcher scripts
# (setup/verify/solve); never executed directly.

# Select the part (run-lab.sh exports LAB_PART; default to the first part).
LAB_PART="${LAB_PART:-single}"
case " ${LAB_PARTS} " in
  *" ${LAB_PART} "*) ;;
  *) die "unknown part '${LAB_PART}'. Available: ${LAB_PARTS}" ;;
esac
# shellcheck source=/dev/null
source "${here}/parts/${LAB_PART}.sh"

# Every check reads the cluster through the admin kubeconfig, so no check depends
# on the kubeconfig the reader sets up.
ak() { sudo kubectl --kubeconfig /etc/kubernetes/admin.conf "$@"; }

# The vagrant user's kubeconfig, with the context the Tier 2 labs expect.
user_kubeconfig() {
  mkdir -p "$HOME/.kube"
  sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
  sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
  kubectl config rename-context "$(kubectl config current-context)" "$LAB_CONTEXT" >/dev/null
}

# Calico at the pinned version, with its IP pool moved off the VM network.
install_calico() {
  curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml" |
    sed -e 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' \
        -e "s|#   value: \"192.168.0.0/16\"|  value: \"${POD_CIDR}\"|" |
    kubectl apply -f - >/dev/null
  kubectl -n kube-system rollout status daemonset/calico-node --timeout=600s >/dev/null
}

# wait_calico <nodes>   calico-node ready on that many nodes
wait_calico() {
  local want=$1
  calico_ready() { [[ "$(kubectl -n kube-system get daemonset calico-node -o jsonpath='{.status.numberReady}')" == "$want" ]]; }
  wait_for "calico-node ready on ${want} nodes" 600 calico_ready
}
