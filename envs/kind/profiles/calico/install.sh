#!/usr/bin/env bash
# Install the components of the `calico` profile (the default). Called by
# tools/cluster.sh with the kubectl context already pointing at the cluster.
# Every step is idempotent, so it also repairs a cluster created elsewhere.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../../tools/lib.sh"

# Calico is the CNI (cluster.yaml disables the default one).
kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml" >/dev/null
kubectl -n kube-system rollout status daemonset/calico-node --timeout=300s >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=300s >/dev/null
info "CNI: Calico ${CALICO_VERSION}; all nodes are Ready"

# metrics-server gives kubectl top and the HPA their numbers (Chapter 25). kind's
# kubelets use self-signed certificates, so the lab's copy skips their verification.
# Applying the manifest first resets the arguments, so the patch adds the flag once.
kubectl apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml" >/dev/null
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' >/dev/null
kubectl -n kube-system rollout status deployment/metrics-server --timeout=300s >/dev/null
info "metrics-server ${METRICS_SERVER_VERSION} is installed"
