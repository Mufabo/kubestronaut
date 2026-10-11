#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"

require_lab_cluster
require_cmd helm
lab_teardown_ns "$LAB_NS"
lab_create_ns "$LAB_NS"

# The chart and the Kustomize sources the tasks use, copied to a place the
# reader can point at. Only these two folders are replaced: .state/ also holds
# the saved kubectl context.
mkdir -p "${here}/.state"
rm -rf "${here}/.state/charts" "${here}/.state/kustomize"
mkdir -p "${here}/.state/charts"
cp -r "${here}/../manifests/charts/shop" "${here}/.state/charts/shop"
cp -r "${here}/../manifests/kustomize" "${here}/.state/kustomize"

info "Lab ready. Namespace: ${LAB_NS}. Chart: lab/.state/charts/shop. Kustomize overlay: lab/.state/kustomize/overlay"
