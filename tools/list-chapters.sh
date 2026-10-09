#!/usr/bin/env bash
# List chapter numbers whose lab declares LAB_TIER=<tier> in lab/lab.env.
#   list-chapters.sh 1
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
want="${1:-1}"
for env in "${root}"/chapters/*/lab/lab.env; do
  [[ -f "$env" ]] || continue
  tier="$(grep -E '^LAB_TIER=' "$env" | cut -d= -f2 | tr -d '"')"
  if [[ "$tier" == "$want" ]]; then
    basename "$(dirname "$(dirname "$env")")" | cut -d- -f1
  fi
done
