#!/usr/bin/env bash
# Print the directory of a lab: a chapter number or a mock exam name.
#   lab-path.sh 4       -> chapters/04-pods
#   lab-path.sh part1   -> mock-exams/part1
# Exactly one chapter directory must match; zero or several is an error.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
n="${1:?usage: lab-path.sh <chapter-number|mock-exam-name>}"
if [[ ! "$n" =~ ^[0-9]+$ ]]; then
  if [[ "$n" =~ ^[a-z0-9][a-z0-9-]*$ && -d "${root}/mock-exams/${n}" ]]; then
    echo "${root}/mock-exams/${n}"; exit 0
  fi
  echo "error: '${n}' is neither a chapter number nor a mock exam in mock-exams/" >&2; exit 1
fi
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
