#!/usr/bin/env bash
# Prepare the `nocni` profile: no CNI is installed (the labs do that), but the
# probe and backend images are copied into the nodes once (see kind_preload).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../../tools/lib.sh"
kind_preload "$NETSHOOT_IMAGE" "$AGNHOST_IMAGE"
