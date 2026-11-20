#!/usr/bin/env bash
# Install the components of the `cilium` profile. Called by tools/cluster.sh
# with the kubectl context already pointing at the new cluster.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../../tools/lib.sh"
require_cmd helm

values=(
  --set ipam.mode=kubernetes
  --set routingMode=tunnel --set tunnelProtocol=vxlan
  --set kubeProxyReplacement=false
  --set hubble.enabled=true --set hubble.relay.enabled=true
  --set operator.replicas=1
  # Tags instead of digests, so the images copied in by kind_preload match.
  --set image.useDigest=false --set operator.image.useDigest=false
  --set hubble.relay.image.useDigest=false --set envoy.image.useDigest=false
)
chart=(cilium --repo https://helm.cilium.io --version "$CILIUM_VERSION" --namespace kube-system)

kind_preload "$NETSHOOT_IMAGE" "$AGNHOST_IMAGE"
info "copying the Cilium ${CILIUM_VERSION} images into the nodes"
mapfile -t images < <(helm template cilium "${chart[@]}" "${values[@]}" | sed -n 's/^ *image: "\(.*\)"$/\1/p' | sort -u)
kind_preload "${images[@]}"

info "installing Cilium ${CILIUM_VERSION} (Helm chart cilium/cilium)"
helm upgrade --install cilium "${chart[@]}" "${values[@]}" --wait --timeout 10m >/dev/null
kubectl -n kube-system rollout status daemonset/cilium --timeout=300s >/dev/null
kubectl -n kube-system rollout status deployment/hubble-relay --timeout=300s >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=300s >/dev/null
kubectl -n kube-system rollout status deployment/coredns --timeout=300s >/dev/null
info "Cilium is running; all nodes are Ready"
