#!/usr/bin/env bash
# Print the namespace(s) a lab (part) owns, read from lab/lab.env.
#   lab-namespaces.sh <snapshot|default> <chapter-number> [part]
# default  -> the single namespace `make use-namespace` selects:
#             LAB_NS_<part> if set, else LAB_NS
# snapshot -> the namespaces CI compares before/after `verify`:
#             LAB_SNAPSHOT_NS_<part>, else LAB_SNAPSHOT_NS (space separated),
#             else the default one
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mode="${1:?snapshot|default}"
dir="$(bash "${here}/lab-path.sh" "${2:?chapter number}")"
part="${3:-}"
[[ -f "${dir}/lab/lab.env" ]] || exit 0
bash -c 'source "$1"; mode=$2; part=$3
  suffix="${part//[^A-Za-z0-9]/_}"
  var="LAB_NS_${suffix}"; pns="${!var:-}"
  svar="LAB_SNAPSHOT_NS_${suffix}"; sns="${!svar:-}"
  if [[ "$mode" == snapshot ]]; then echo "${sns:-${LAB_SNAPSHOT_NS:-${pns:-${LAB_NS:-}}}}"
  else echo "${pns:-${LAB_NS:-}}"; fi' _ "${dir}/lab/lab.env" "$mode" "$part"
