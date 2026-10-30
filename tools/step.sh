#!/usr/bin/env bash
# Step-by-step lab runner, in the style of KodeKloud's labs: one task at a time,
# a Check that tests only the current task, and progress that carries over.
#   step.sh <chapter-number|exam-name> <start|question|check|skip|clear|count|mode> [part]
#
#   start     go back to task 1 and print it (make lab / make reset call this)
#   question  print the current task again
#   check     check only the current task; if it is correct, move on and print
#             the next one, otherwise print the hint
#   skip      move on without checking (useful for optional tasks)
#   clear     forget the progress (make teardown calls this)
#   count     print the number of tasks
#   mode      print "task" (step by step) or "question" (exam style)
#
# The tasks are read from the chapter text itself: the "### Task ..." headings
# in its "## Hands-on lab" section, or, for a lab with parts, the
# "#### Task ..." headings under "### Part <part>: ...". Task N in the text is
# check N in verify.sh; CI walks every lab through all of its steps to prove
# the two line up.
#
# A lab whose headings are "Question N | ..." instead of "Task ..." is exam
# style (killer.sh): no step-by-step checks, all questions scored at once by
# verify. Mock exams (mock-exams/<name>/<name>.md) are always exam style.
#
# Exit codes: 0 = done / correct, 1 = not yet correct, 2 = usage or lab error.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/lib.sh"
ch="${1:?chapter number}"
action="${2:?start|question|check|skip|clear|count|mode}"
part="${3:-${LAB_PART:-}}"

usage_error() { printf '%s\n' "error: $*" >&2; exit 2; }

dir="$(bash "${here}/lab-path.sh" "$ch")" || exit 2
parts="$(bash "${here}/lab-parts.sh" "$ch")" || exit 2
if [[ -n "$parts" ]]; then
  [[ -n "$part" ]] || part="${parts%% *}"
  case " ${parts} " in
    *" ${part} "*) ;;
    *) usage_error "unknown part '${part}' for chapter ${ch}. Available: ${parts}" ;;
  esac
elif [[ -n "$part" ]]; then
  usage_error "chapter ${ch} has no parts, but part '${part}' was requested"
fi

text="${dir}/$(basename "$dir").md"
[[ -f "$text" ]] || usage_error "chapter text not found: ${text}"
state="${dir}/lab/.state/step${part:+-${part}}"
if [[ "$ch" =~ ^[0-9]+$ ]]; then
  make_args="CH=$((10#$ch))${part:+ PART=${part}}"; score_cmd="make verify ${make_args}"; mock=0
else
  make_args="EXAM=${ch}"; score_cmd="make mock-score ${make_args}"; mock=1
fi

# tasks <n>   print task n (heading and body); with n=0, print "<count> <kind>"
# where kind is task (step by step), question (exam style), mixed, or none.
# A mock exam's whole file holds "## Question" headings; a chapter's lab
# section holds "### Task" or "### Question" headings ("####" under a part).
tasks() {
  awk -v want="$1" -v part="$part" -v mock="$mock" '
    function heading(line, level) {
      if (index(line, level "Task ") == 1)     { tk++; return 1 }
      if (index(line, level "Question ") == 1) { qs++; return 1 }
      return 0
    }
    mock == 1 {
      if (heading($0, "## ")) { n++; intask = (n == want); if (intask) print; next }
      if ($0 ~ /^#+ /) { intask = 0; next }
      if (intask) print
      next
    }
    /^## /                { inlab = ($0 == "## Hands-on lab"); inpart = 0; intask = 0; next }
    !inlab                { next }
    part != "" && /^### / { inpart = (index($0, "### Part " part ":") == 1); intask = 0; next }
    part != "" && !inpart { next }
    {
      level = (part == "") ? "### " : "#### "
      if (heading($0, level)) { n++; intask = (n == want); if (intask) print; next }
      if ($0 ~ /^#+ /) { intask = 0; next }
      if (intask) print
    }
    END {
      if (want == 0) print n + 0, (tk && qs) ? "mixed" : tk ? "task" : qs ? "question" : "none"
    }
  ' "$text"
}

read -r count kind < <(tasks 0)
((count > 0)) || usage_error "no tasks found in ${text}"
[[ "$kind" != mixed ]] || usage_error "${text} mixes Task and Question headings in one lab"

# Exam style (killer.sh): all questions at once, scored together with verify.
exam_banner() {
  printf '%s\n' "${C_DIM}── Exam style: ${count} questions ───────────────────────${C_RST}"
  printf '%s\n' "Answer them in any order, as in the exam. The questions are in"
  printf '%s\n' "${text#"${BOOK_ROOT}"/}${part:+ (Part ${part})}. Score yourself with: ${score_cmd}"
}

current() {
  local n=1
  [[ -f "$state" ]] && n="$(cat "$state")"
  [[ "$n" =~ ^[0-9]+$ ]] || n=1
  printf '%s' "$n"
}
save() { mkdir -p "$(dirname "$state")"; printf '%s' "$1" > "$state"; }

complete_message() {
  printf '%s\n' "${C_GRN}Lab complete: all ${count} tasks done.${C_RST}"
  printf '%s\n' "Run 'make verify ${make_args}' to check every task again at once, or 'make teardown ${make_args}' to clean up."
}

show() {
  local n=$1 body
  if ((n > count)); then complete_message; return 0; fi
  body="$(tasks "$n" | sed -e 's/`//g' -e 's/\*\*//g' -e 's/^#* *//')"
  echo
  printf '%s\n' "${C_DIM}── Task ${n} of ${count} ───────────────────────────────${C_RST}"
  # Trim blank lines at the end of the block.
  printf '%s\n' "$body" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
  echo
  printf '%s\n' "${C_DIM}Done? make check ${make_args}    Again: make question ${make_args}${C_RST}"
}

case "$action" in
  count) echo "$count"; exit 0 ;;
  mode)  echo "$kind"; exit 0 ;;
esac
if [[ "$kind" == question ]]; then
  case "$action" in
    start|question) exam_banner; exit 0 ;;
    clear)          rm -f "$state"; exit 0 ;;
    check|skip)     exam_banner >&2; usage_error "this lab is exam style: no per-question checks" ;;
    *)              usage_error "unknown action '${action}'" ;;
  esac
fi
case "$action" in
  start)    save 1; show 1 ;;
  question) show "$(current)" ;;
  clear)    rm -f "$state" ;;
  skip)
    n="$(current)"
    if ((n > count)); then complete_message; exit 0; fi
    save $((n + 1)); info "Skipped task ${n}."; show $((n + 1)) ;;
  check)
    n="$(current)"
    if ((n > count)); then complete_message; exit 0; fi
    rc=0
    out="$(LAB_ONLY_TASK="$n" bash "${here}/run-lab.sh" "$ch" verify "$part" 2>&1)" || rc=$?
    if ((rc == 2)); then printf '%s\n' "$out" >&2; exit 2; fi
    if ((rc == 0)) && [[ "$out" != *TODO* ]]; then
      printf '%s\n' "${C_GRN}Correct!${C_RST} Task ${n} of ${count} done."
      save $((n + 1)); show $((n + 1)); exit 0
    fi
    printf '%s\n' "${C_RED}Not yet.${C_RST}"
    grep -E 'FAIL|TODO|hint:|debug|^ {10}' <<<"$out" || true
    if [[ "$out" == *TODO* ]]; then
      echo "This task is optional: 'make skip ${make_args}' moves on without it."
    fi
    exit 1 ;;
  *) usage_error "unknown action '${action}'" ;;
esac
