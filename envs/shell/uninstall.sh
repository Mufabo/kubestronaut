#!/usr/bin/env bash
# Remove what install.sh added.
#
#   envs/shell/uninstall.sh [--rc FILE] [--vimrc FILE] [--no-vim]
#
# Removes only the marked blocks. If a file existed before install it keeps its
# other content (and its .kbook-backup copy stays, for safety); a file that
# install.sh created and that is now empty is deleted.
set -euo pipefail

start_rc='# >>> kbook shell setup (managed block; remove with envs/shell/uninstall.sh) >>>'
end_rc='# <<< kbook shell setup <<<'
start_vim='" >>> kbook vim setup (managed block; remove with envs/shell/uninstall.sh) >>>'
end_vim='" <<< kbook vim setup <<<'

rc=""; vimrc="${HOME}/.vimrc"; do_vim=1
while (($#)); do
  case "$1" in
    --rc)     rc="${2:?--rc needs a file}"; shift 2 ;;
    --vimrc)  vimrc="${2:?--vimrc needs a file}"; shift 2 ;;
    --no-vim) do_vim=0; shift ;;
    -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$rc" ]]; then
  case "$(basename "${SHELL:-bash}")" in zsh) rc="${HOME}/.zshrc" ;; *) rc="${HOME}/.bashrc" ;; esac
fi

remove_block() { # remove_block <file> <start> <end>
  local file=$1 start=$2 end=$3 tmp
  [[ -f "$file" ]] || { echo "nothing to do: ${file} does not exist"; return 0; }
  if ! grep -Fxq -- "$start" "$file"; then echo "nothing to do: no managed block in ${file}"; return 0; fi
  tmp="$(mktemp)"
  awk -v s="$start" -v e="$end" '$0==s{skip=1; next} skip&&$0==e{skip=0; next} !skip{print}' "$file" > "$tmp"
  if [[ ! -s "$tmp" && ! -f "${file}.kbook-backup" ]]; then
    rm -f "$file" "$tmp"; echo "removed ${file} (install.sh had created it)"
  else
    cat "$tmp" > "$file"; rm -f "$tmp"; echo "cleaned ${file}"
  fi
}

remove_block "$rc" "$start_rc" "$end_rc"
((do_vim)) && remove_block "$vimrc" "$start_vim" "$end_vim"
echo "Done. Open a new shell for the change to take effect."
