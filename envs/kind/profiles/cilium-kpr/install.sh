#!/usr/bin/env bash
# Install the components of the `cilium-kpr` profile. Called by tools/cluster.sh
# with the kubectl context already pointing at the new cluster.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../../tools/lib.sh"
require_cmd helm

# Without kube-proxy, nothing makes the kubernetes Service's ClusterIP work
# until Cilium runs, so Cilium talks to the API server on the control plane
# node directly (its name resolves on the kind network).
values=(
  --set kubeProxyReplacement=true
  --set k8sServiceHost="${CLUSTER_NAME}-control-plane" --set k8sServicePort=6443
  --set ipam.mode=kubernetes
  --set routingMode=tunnel --set tunnelProtocol=vxlan
  # The egress gateway (Chapter 60) needs Cilium's own BPF masquerading.
  --set bpf.masquerade=true --set egressGateway.enabled=true
  # LoadBalancer IPs from LB-IPAM pools, announced with ARP on the kind network.
  --set l2announcements.enabled=true
  --set k8sClientRateLimit.qps=10 --set k8sClientRateLimit.burst=20
  --set gatewayAPI.enabled=true
  --set hubble.enabled=true --set hubble.relay.enabled=true
  --set operator.replicas=1
  # Tags instead of digests, so the images copied in by kind_preload match.
  --set image.useDigest=false --set operator.image.useDigest=false
  --set hubble.relay.image.useDigest=false --set envoy.image.useDigest=false
)
chart=(cilium --repo https://helm.cilium.io --version "$CILIUM_VERSION" --namespace kube-system)

# The Gateway API CRDs must exist before Cilium starts, or its Gateway API
# controller stays off. The standard channel includes TLSRoute since v1.5.
info "installing the Gateway API ${GATEWAY_API_VERSION} CRDs (standard channel)"
kubectl apply --server-side \
  -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml" >/dev/null

kind_preload "$NETSHOOT_IMAGE" "$AGNHOST_IMAGE"
info "copying the Cilium ${CILIUM_VERSION} images into the nodes"
mapfile -t images < <(helm template cilium "${chart[@]}" "${values[@]}" | sed -n 's/^ *image: "\(.*\)"$/\1/p' | sort -u)
kind_preload "${images[@]}"

info "installing Cilium ${CILIUM_VERSION} with kube-proxy replacement (Helm chart cilium/cilium)"
helm upgrade --install cilium "${chart[@]}" "${values[@]}" --wait --timeout 10m >/dev/null
kubectl -n kube-system rollout status daemonset/cilium --timeout=300s >/dev/null
kubectl -n kube-system rollout status daemonset/cilium-envoy --timeout=300s >/dev/null
kubectl -n kube-system rollout status deployment/hubble-relay --timeout=300s >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=300s >/dev/null
kubectl -n kube-system rollout status deployment/coredns --timeout=300s >/dev/null
info "Cilium is running without kube-proxy; all nodes are Ready"
