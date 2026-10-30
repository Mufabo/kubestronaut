#!/usr/bin/env bash
# Run one of a lab's scripts. A lab is a chapter (by number) or a mock exam
# (by name, from mock-exams/).
#   run-lab.sh <chapter-number|exam-name> <setup|reset|verify|solve|teardown|use-namespace> [part]
#
# Labs may be split into parts (LAB_PARTS="a b1 b2" in lab/lab.env). The part
# comes from the third argument or $LAB_PART; if omitted, the first part is
# used. The chosen part is exported to the lab script as LAB_PART.
#
# Exit codes: 2 = usage error (bad part, missing script); anything else comes
# from the lab script itself.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ch="${1:?chapter number (CH=n) or mock exam name (EXAM=name)}"
action="${2:?setup|reset|verify|solve|teardown}"
part="${3:-${LAB_PART:-}}"

dir="$(bash "${here}/lab-path.sh" "$ch")"
parts="$(bash "${here}/lab-parts.sh" "$ch")"

if [[ -n "$parts" ]]; then
  if [[ -z "$part" ]]; then
    part="${parts%% *}"
    echo "==> no part given; using '${part}' (available: ${parts})" >&2
  fi
  case " ${parts} " in
    *" ${part} "*) ;;
    *) echo "error: unknown part '${part}' for chapter ${ch}. Available: ${parts}" >&2; exit 2 ;;
  esac
elif [[ -n "$part" ]]; then
  echo "error: chapter ${ch} has no parts, but part '${part}' was requested" >&2
  exit 2
fi
export LAB_PART="$part"

# use-namespace is generic (tools/use-namespace.sh); no per-lab script needed.
if [[ "$action" == "use-namespace" ]]; then
  exec bash "${here}/use-namespace.sh" "$ch"
fi

# Tier 2 labs reset by restoring a VM snapshot, which only the host can do.
if [[ "$action" == reset && -f "${dir}/lab/lab.env" ]]; then
  read -r tier snap < <(bash -c 'source "$1"; printf "%s %s\n" "${LAB_TIER:-1}" "${LAB_SNAPSHOT:-cluster}"' _ "${dir}/lab/lab.env")
  if [[ "$tier" == 2 ]]; then
    echo "Tier 2 labs reset by restoring the VMs' snapshot. On the host, run:" >&2
    printf '  envs/vagrant/kbook-vm restore %s      (Windows: .\\envs\\vagrant\\kbook-vm.ps1 restore %s)\n' "$snap" "$snap" >&2
    echo "then, back on cp1: make lab CH=${ch}${part:+ PART=${part}}" >&2
    exit 2
  fi
fi

script="${dir}/lab/${action}.sh"
# Multiple-choice practice exams (mock-exams/<name>/quiz.yaml) have no lab.
if [[ ! -d "${dir}/lab" && -f "${dir}/quiz.yaml" ]]; then
  echo "error: ${ch} is a multiple-choice practice exam with no lab; run: make quiz EXAM=${ch}" >&2
  exit 2
fi
if [[ ! -f "$script" ]]; then
  if [[ "$action" == "teardown" ]]; then
    echo "==> this lab has no teardown script; nothing to do"
    exit 0
  fi
  echo "error: missing ${script}" >&2
  exit 2
fi
exec bash "$script"
