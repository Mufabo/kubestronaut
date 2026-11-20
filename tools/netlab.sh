#!/usr/bin/env bash
# Manage the Tier 0 netlab container (Part V labs).
#   netlab.sh build      build the image if it does not exist yet (FORCE=1 rebuilds)
#   netlab.sh up         make sure the container is running (creates it if needed)
#   netlab.sh recreate   throw the container away and start a fresh one
#   netlab.sh shell      open a shell inside it (starts it first if needed)
#   netlab.sh down       remove the container
#   netlab.sh status     say whether the image and container exist
#
# The container runs with --network none: it has no connection to your
# machine's network or the internet. Every "network" in Part V is built inside
# it out of network namespaces, so nothing you do in a lab can affect your
# machine's networking, and every reader sees the same addresses.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/lib.sh"
require_cmd docker

action="${1:-status}"

image_exists()     { docker image inspect "$NETLAB_IMAGE" >/dev/null 2>&1; }
container_exists() { docker container inspect "$NETLAB_CONTAINER" >/dev/null 2>&1; }
container_running() {
  [[ "$(docker container inspect -f '{{.State.Running}}' "$NETLAB_CONTAINER" 2>/dev/null)" == true ]]
}

build() {
  if image_exists && [[ "${FORCE:-0}" != 1 ]]; then return 0; fi
  info "Building ${NETLAB_IMAGE} from envs/netlab (first time only; takes a minute or two)"
  docker build --build-arg "BASE_IMAGE=${NETLAB_BASE_IMAGE}" -t "$NETLAB_IMAGE" "${BOOK_ROOT}/envs/netlab"
}

create() {
  build
  docker run -d --name "$NETLAB_CONTAINER" --hostname netlab \
    --label kubestronaut.io/lab=netlab --privileged --network none \
    -v "${BOOK_ROOT}/envs/netlab/rootfs:/opt/netlab:ro" \
    "$NETLAB_IMAGE" >/dev/null
  wait_for "the netlab container to start" 30 container_running
}

case "$action" in
  build) build ;;
  up)
    if container_running; then exit 0; fi
    if container_exists; then docker start "$NETLAB_CONTAINER" >/dev/null; else create; fi
    ;;
  recreate)
    if container_exists; then netlab_guard; docker rm -f "$NETLAB_CONTAINER" >/dev/null; fi
    create
    ;;
  shell)
    bash "$0" up
    exec docker exec -it -w /root "$NETLAB_CONTAINER" bash
    ;;
  down)
    if container_exists; then netlab_guard; docker rm -f "$NETLAB_CONTAINER" >/dev/null; info "netlab container removed"; fi
    ;;
  status)
    if image_exists; then echo "image:     ${NETLAB_IMAGE} (built)"; else echo "image:     ${NETLAB_IMAGE} (not built; make netlab)"; fi
    if container_running; then echo "container: ${NETLAB_CONTAINER} (running)"
    elif container_exists; then echo "container: ${NETLAB_CONTAINER} (stopped)"
    else echo "container: ${NETLAB_CONTAINER} (none)"; fi
    ;;
  *) die "unknown action '${action}' (build|up|recreate|shell|down|status)" ;;
esac
