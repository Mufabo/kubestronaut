# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2153  # variables come from the sourcing script and lab.env
# Shared by the Chapter 36 lab parts. Sourced by the dispatcher scripts
# (setup/verify/solve/teardown); never executed directly.

STATE="${here}/.state"

# Select the part (run-lab.sh exports LAB_PART; default to the first part).
LAB_PART="${LAB_PART:-policy}"
case " ${LAB_PARTS} " in
  *" ${LAB_PART} "*) ;;
  *) die "unknown part '${LAB_PART}'. Available: ${LAB_PARTS}" ;;
esac
# shellcheck source=/dev/null
source "${here}/parts/${LAB_PART}.sh"
