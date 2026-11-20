#!/usr/bin/env bash
# Manage the Tier 1 kind cluster and its profiles (envs/kind/profiles/).
#   cluster.sh [up] [<profile>]   make sure the cluster runs <profile> (default:
#                                 calico, the cluster of Parts I to IV); reuses a
#                                 healthy cluster of that profile, otherwise
#                                 (re)creates it
#   cluster.sh fresh <profile>    always delete and recreate the cluster
#   cluster.sh down               delete the cluster
#   cluster.sh status             print the cluster's profile and node states
#
# A profile is a folder with a kind config (cluster.yaml) and an optional
# install.sh that adds the CNI and other components. When the cluster is ready,
# the ConfigMap kube-system/kbook-lab-marker records the cluster name and the
# profile; lab scripts refuse to touch a cluster without it (tools/lib.sh).
# A marker without a profile (written before profiles existed) means calico.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/lib.sh"
require_cmd docker kind kubectl

action="${1:-up}"
profile="${2:-${LAB_PROFILE:-$LAB_DEFAULT_PROFILE}}"
ctx="kind-${CLUSTER_NAME}"
profiles_dir="${BOOK_ROOT}/envs/kind/profiles"

cluster_exists() { [[ " $(kind get clusters 2>/dev/null | xargs) " == *" ${CLUSTER_NAME} "* ]]; }
marker_field() {
  kubectl --context "$ctx" -n kube-system get configmap "$LAB_MARKER_NAME" \
    -o jsonpath="{.data.$1}" 2>/dev/null || true
}
running_version() {
  kubectl --context "$ctx" get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' 2>/dev/null || true
}

available() { local d out=(); for d in "${profiles_dir}"/*/; do d="${d%/}"; out+=("${d##*/}"); done; echo "${out[*]}"; }

check_profile() {
  [[ -n "$profile" ]] || die "no profile given. Available: $(available)"
  [[ -f "${profiles_dir}/${profile}/cluster.yaml" ]] ||
    die "unknown profile '${profile}'. Available: $(available)"
}

delete() {
  if cluster_exists; then
    info "deleting kind cluster ${CLUSTER_NAME}"
    kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1
  fi
}

write_marker() {
  kubectl --context "$ctx" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${LAB_MARKER_NAME}
  namespace: kube-system
  labels:
    kubestronaut.io/environment: lab
data:
  cluster: ${CLUSTER_NAME}
  profile: ${1}
YAML
}

# The most common failure: every kind node runs systemd, which needs inotify
# instances, and Linux allows only 128 per user by default. With another kind
# cluster (or an IDE) running, the new nodes die with "Too many open files".
create_failed() {
  local limit
  limit="$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)"
  if ((limit < 512)); then
    die "kind could not create the cluster. Your inotify limit is ${limit} instances (fs.inotify.max_user_instances); kind needs about 512 when more than one cluster runs. Raise it, then try again:
    sudo sysctl fs.inotify.max_user_instances=512 fs.inotify.max_user_watches=524288
  (To keep it after a reboot: put both settings in /etc/sysctl.d/99-kind.conf.)"
  fi
  die "kind could not create the cluster. Run it by hand to see why: kind create cluster --name ${CLUSTER_NAME} --config envs/kind/profiles/${profile}/cluster.yaml --retain, then docker logs ${CLUSTER_NAME}-control-plane"
}

create() {
  info "creating kind cluster ${CLUSTER_NAME} with profile '${profile}' (${KIND_NODE_IMAGE}); this takes a minute or two"
  kind create cluster --name "$CLUSTER_NAME" --image "$KIND_NODE_IMAGE" \
    --config "${profiles_dir}/${profile}/cluster.yaml" --wait 0s >/dev/null 2>&1 || create_failed
  kubectl config use-context "$ctx" >/dev/null
  wait_for "the API server" 120 kubectl --context "$ctx" get --raw=/readyz
  # Mark the cluster at once, with the profile still "installing:<name>", so a
  # cluster whose install failed is still recognized (and rebuilt) as ours.
  write_marker "installing:${profile}"
  if [[ -f "${profiles_dir}/${profile}/install.sh" ]]; then
    bash "${profiles_dir}/${profile}/install.sh"
  fi
  write_marker "$profile"
  info "cluster ${CLUSTER_NAME} is ready (profile '${profile}', context ${ctx})"
}

case "$action" in
  up)
    check_profile
    if cluster_exists; then
      kubectl --context "$ctx" get --raw=/readyz >/dev/null 2>&1 ||
        die "the kind cluster ${CLUSTER_NAME} exists but its API server does not answer (after a reboot its node containers may be stopped). Start them with: docker start \$(docker ps -aq --filter label=io.x-k8s.kind.cluster=${CLUSTER_NAME}), or rebuild it with: make cluster-delete"
      have="$(marker_field profile)" version="$(running_version)"
      if [[ -z "$have" && "$(marker_field cluster)" == "$CLUSTER_NAME" ]]; then
        have="$LAB_DEFAULT_PROFILE"   # marked before profiles existed
        [[ "$profile" == "$have" && "$version" == "$K8S_VERSION" ]] && write_marker "$have"
      fi
      if [[ "$have" == "$profile" && "$version" == "$K8S_VERSION" ]]; then
        kubectl config use-context "$ctx" >/dev/null
        info "cluster ${CLUSTER_NAME} already runs profile '${profile}'"
        exit 0
      fi
      if [[ "$(marker_field cluster)" != "$CLUSTER_NAME" ]]; then
        die "a kind cluster named ${CLUSTER_NAME} exists but is not marked as this book's lab cluster; delete it yourself if it is disposable: kind delete cluster --name ${CLUSTER_NAME}"
      fi
      if [[ "$version" != "$K8S_VERSION" ]]; then
        info "cluster ${CLUSTER_NAME} runs Kubernetes ${version:-unknown}, but versions.env pins ${K8S_VERSION}, so it is recreated"
      else
        info "cluster ${CLUSTER_NAME} runs profile '${have:-unknown}'; '${profile}' was asked for, so it is recreated"
      fi
      delete
    fi
    create
    ;;
  fresh)
    check_profile
    delete
    create
    ;;
  down|delete)
    delete
    ;;
  status)
    if ! cluster_exists; then echo "cluster ${CLUSTER_NAME}: not created (make cluster PROFILE=<name>)"; exit 0; fi
    echo "cluster ${CLUSTER_NAME}: profile '$(marker_field profile)', Kubernetes $(running_version), context ${ctx}"
    kubectl --context "$ctx" get nodes -o wide
    ;;
  *)
    die "usage: cluster.sh [up|fresh] [<profile>] | down | status"
    ;;
esac
