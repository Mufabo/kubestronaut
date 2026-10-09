# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2153  # variables come from the sourcing script and lab.env
# Shared helpers for the Chapter 03 lab parts. Sourced by the dispatcher
# scripts (setup/verify/solve/teardown); never executed directly.

STATE="${here}/.state"
MANIFESTS="${here}/../manifests"

# Select the part (run-lab.sh exports LAB_PART; default to the first part).
LAB_PART="${LAB_PART:-a}"
case " ${LAB_PARTS} " in
  *" ${LAB_PART} "*) ;;
  *) die "unknown part '${LAB_PART}'. Available: ${LAB_PARTS}" ;;
esac
# shellcheck source=/dev/null
source "${here}/parts/${LAB_PART}.sh"

# The kubectl context this lab expects (Tier 1: kind-<cluster>).
base_context() { printf '%s' "${LAB_CONTEXT:-kind-${CLUSTER_NAME}}"; }

# jpod <namespace> <pod> <jsonpath>   print a field of one Pod
jpod() { kubectl -n "$1" get pod "$2" -o "jsonpath=$3"; }

# one_container <namespace> <pod>   true if the Pod has exactly one container
one_container() {
  local names
  names="$(jpod "$1" "$2" '{.spec.containers[*].name}')" || return 1
  [[ -n "$names" && "$names" != *" "* ]]
}

# wait_running <namespace> <pod>...
wait_running() {
  local ns=$1 p; shift
  for p in "$@"; do
    wait_for "pod ${p} Running" 240 pod_phase_is "$ns" "$p" Running
  done
}

# file_token <file>   the file's content without any whitespace
file_token() { tr -d '[:space:]' < "$1"; }

# norm_list <file>   sorted, de-duplicated, trimmed, non-empty lines;
#                    a leading "pod/" (as printed by -o name) is ignored
norm_list() {
  grep -v '^[[:space:]]*$' "$1" | sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's#^pod/##' | sort -u
}

# random_token   8 random lowercase letters/digits (fails loudly if it cannot)
random_token() {
  local t
  t="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 8 || true)"
  [[ ${#t} -eq 8 ]] || die "failed to generate a random token"
  printf '%s' "$t"
}

# in_contains <needle> <haystack>   whole-word membership in a space-separated list
word_in() { [[ " $2 " == *" $1 "* ]]; }
