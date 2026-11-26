# shellcheck shell=bash
# Shared by setup and teardown. Sourced after lib.sh and lab.env.

# The VPA recommender at VPA_VERSION, without the updater and the admission
# controller: enough for a VPA in Off mode, which only recommends.
vpa_manifests() {
  local base="https://raw.githubusercontent.com/kubernetes/autoscaler/vertical-pod-autoscaler-${VPA_VERSION}/vertical-pod-autoscaler/deploy"
  echo "${base}/vpa-v1-crd-gen.yaml ${base}/vpa-rbac.yaml ${base}/recommender-deployment.yaml"
}

install_vpa() {
  local url
  info "Installing the VPA recommender ${VPA_VERSION}"
  for url in $(vpa_manifests); do
    curl -fsSL "$url" | kubectl apply -f - >/dev/null
  done
  kubectl -n kube-system rollout status deployment/vpa-recommender --timeout=180s >/dev/null
}

# Safe when nothing is installed. The CRDs go last, which also removes every VPA object.
remove_vpa() {
  local urls url i
  read -r -a urls <<<"$(vpa_manifests)"
  for ((i = ${#urls[@]} - 1; i >= 0; i--)); do
    url="${urls[$i]}"
    curl -fsSL "$url" | kubectl delete --ignore-not-found --wait=true -f - >/dev/null 2>&1 || true
  done
}
