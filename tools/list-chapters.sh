#!/usr/bin/env bash
# List chapter numbers (or, with --mocks, mock exam names) whose lab declares
# LAB_TIER=<tier> in lab/lab.env, optionally only those on the given cluster
# profiles (LAB_PROFILE, default calico).
#   list-chapters.sh 1
#   list-chapters.sh 1 calico
#   list-chapters.sh --mocks 1 nocni cilium
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kind=chapters
if [[ "${1:-}" == --mocks ]]; then kind=mock-exams; shift; fi
envs=("${root}/${kind}"/*/lab/lab.env)
want="${1:-1}"; shift || true
profiles=" $* "
for env in "${envs[@]}"; do
  [[ -f "$env" ]] || continue
  read -r tier profile < <(bash -c 'source "$1"; printf "%s %s\n" "${LAB_TIER:-1}" "${LAB_PROFILE:-calico}"' _ "$env")
  [[ "$tier" == "$want" ]] || continue
  [[ "$profiles" == "  " || "$profiles" == *" ${profile} "* ]] || continue
  name="$(basename "$(dirname "$(dirname "$env")")")"
  if [[ "$kind" == chapters ]]; then echo "${name%%-*}"; else echo "$name"; fi
done
