#!/usr/bin/env bash
# Print the space-separated parts a chapter's lab declares (LAB_PARTS in
# lab/lab.env), or nothing if the lab has no parts.
#   lab-parts.sh <chapter-number>
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="$(bash "${here}/lab-path.sh" "${1:?chapter number}")"
env_file="${dir}/lab/lab.env"
[[ -f "$env_file" ]] || exit 0
# Source in a subshell so nothing leaks into the caller.
bash -c 'source "$1"; printf "%s" "${LAB_PARTS:-}"' _ "$env_file"
