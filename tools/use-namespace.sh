#!/usr/bin/env bash
# Opt in to kubectl defaulting to a lab's namespace.
#   use-namespace.sh <chapter-number>      (part via $LAB_PART)
# Saves your original context/namespace first; `make teardown` restores them.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/lib.sh"
ch="${1:?chapter number}"
dir="$(bash "${here}/lab-path.sh" "$ch")"
ns="$(bash "${here}/lab-namespaces.sh" default "$ch" "${LAB_PART:-}")"
[[ -n "$ns" ]] || die "this lab does not declare a namespace (LAB_NS in lab/lab.env)"
require_lab_cluster
lab_save_kubectx "${dir}/lab/.state/kubectx"
kubectl config set-context --current --namespace="$ns" >/dev/null
if [[ "$ch" =~ ^[0-9]+$ ]]; then undo="make teardown CH=${ch}"; else undo="make mock-teardown EXAM=${ch}"; fi
info "kubectl now defaults to namespace '${ns}'. Undo with: ${undo}"
