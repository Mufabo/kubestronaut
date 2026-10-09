#!/usr/bin/env bash
# Print the chapter directory for a chapter number, e.g. `lab-path.sh 4` -> chapters/04-pods
# Exactly one directory must match; zero or several is an error.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
n="${1:?usage: lab-path.sh <chapter-number>}"
n="$(printf '%02d' "$((10#$n))")"
matches=()
for d in "${root}"/chapters/"${n}"-*/; do
  [[ -d "$d" ]] && matches+=("${d%/}")
done
if ((${#matches[@]} == 0)); then
  echo "error: no chapter directory matches chapters/${n}-*" >&2; exit 1
elif ((${#matches[@]} > 1)); then
  echo "error: chapter number ${n} is ambiguous; matches: ${matches[*]}" >&2; exit 1
fi
echo "${matches[0]}"
