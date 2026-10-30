#!/usr/bin/env bash
# End the lab: remove everything it created and restore the reader's kubectl
# context/namespace if they opted in with `make use-namespace`.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
# remove_lab_image: the image Task 1 loads is removed from every kind node and from
# the local Docker, so that a reset really returns to the starting state.
remove_lab_image() {
  local node repo
  repo="docker.io/library/${LAB_IMAGE%%:*}:${LAB_IMAGE##*:}"
  while IFS= read -r node; do
    docker exec "$node" crictl rmi "$repo" >/dev/null 2>&1 || true
  done < <(kind get nodes --name "$CLUSTER_NAME" 2>/dev/null)
  docker rmi -f "$LAB_IMAGE" >/dev/null 2>&1 || true
}
remove_lab_image
rm -rf "${here}/.state/app"
lab_restore_kubectx "${here}/.state/kubectx"
info "Lab removed."
