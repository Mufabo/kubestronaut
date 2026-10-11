#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
lab_teardown_ns "$LAB_NS"
lab_create_ns "$LAB_NS"

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

# The build context for Task 1. Only this folder is replaced: .state/ also holds
# the saved kubectl context.
rm -rf "${here}/.state/app"
mkdir -p "${here}/.state/app"
cat > "${here}/.state/app/Dockerfile" <<'DOCKER'
FROM nginx:1.27-alpine
RUN echo 'hello from ch16' > /usr/share/nginx/html/index.html
DOCKER

# A Deployment that Task 3 changes to the Recreate strategy.
kubectl -n "$LAB_NS" create deployment legacy --image=nginx:1.26 >/dev/null
kubectl -n "$LAB_NS" rollout status deployment/legacy --timeout=180s >/dev/null

info "Lab ready. Namespace: ${LAB_NS}. Build context: lab/.state/app"
