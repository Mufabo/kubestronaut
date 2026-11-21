#!/usr/bin/env bash
# Chapter 51 lab: a brand-new cilium cluster with the macvlan, ipvlan, bridge,
# and static CNI plugins on every node, and Multus installed. Cilium's default
# cni-exclusive mode has moved Multus's configuration aside on every node, so
# secondary networks are silently ignored.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

cluster_fresh "$LAB_PROFILE"
install_cni_plugins "$here"

info "installing Multus ${MULTUS_VERSION} (thick plugin)"
curl -fsSL "https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/${MULTUS_VERSION}/deployments/multus-daemonset-thick.yml" |
  sed "s|ghcr.io/k8snetworkplumbingwg/multus-cni:snapshot-thick|ghcr.io/k8snetworkplumbingwg/multus-cni:${MULTUS_VERSION}-thick|" |
  kubectl apply -f - >/dev/null
kubectl -n kube-system rollout status daemonset/kube-multus-ds --timeout=300s >/dev/null

# Cilium's agents rename other plugins' configurations when they start.
kubectl -n kube-system rollout restart daemonset/cilium >/dev/null
kubectl -n kube-system rollout status daemonset/cilium --timeout=300s >/dev/null
multus_moved_aside() {
  local n
  for n in $(kind_nodes); do [[ "$(first_cni_conf "$n")" == 05-cilium.conflist ]] || return 1; done
}
wait_for "Cilium to take over the CNI configuration" 120 multus_moved_aside

lab_create_ns "$LAB_NS"
info "Lab ready. Starting manifests for Task 3: chapters/51-multus/manifests/"
