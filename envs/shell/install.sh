#!/usr/bin/env bash
# Add the practice-shell helpers to your shell startup file (and optionally vim).
#
#   envs/shell/install.sh [--rc FILE] [--vimrc FILE] [--no-vim] [--print]
#
# What it does, and only this:
#   * appends ONE clearly marked block to your rc file (default: ~/.zshrc if
#     your login shell is zsh, else ~/.bashrc) that sources kubectl-exam.sh
#   * appends one marked block to ~/.vimrc that sources envs/shell/vimrc
#   * keeps a one-time backup next to each file it changes (FILE.kbook-backup)
#   * is idempotent: running it again replaces the block, never duplicates it
# --print shows the blocks and changes nothing. Undo everything with uninstall.sh.
# Supported: Linux, macOS, and WSL2. Files should end with a newline.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
start_rc='# >>> kbook shell setup (managed block; remove with envs/shell/uninstall.sh) >>>'
end_rc='# <<< kbook shell setup <<<'
start_vim='" >>> kbook vim setup (managed block; remove with envs/shell/uninstall.sh) >>>'
end_vim='" <<< kbook vim setup <<<'

rc=""; vimrc="${HOME}/.vimrc"; do_vim=1; print_only=0
while (($#)); do
  case "$1" in
    --rc)     rc="${2:?--rc needs a file}"; shift 2 ;;
    --vimrc)  vimrc="${2:?--vimrc needs a file}"; shift 2 ;;
    --no-vim) do_vim=0; shift ;;
    --print)  print_only=1; shift ;;
    -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$rc" ]]; then
  case "$(basename "${SHELL:-bash}")" in zsh) rc="${HOME}/.zshrc" ;; *) rc="${HOME}/.bashrc" ;; esac
fi

block_rc() { printf '%s\nsource "%s/kubectl-exam.sh"\n%s\n' "$start_rc" "$here" "$end_rc"; }
block_vim() { printf '%s\nsource %s/vimrc\n%s\n' "$start_vim" "$here" "$end_vim"; }

# strip_block <file> <start-line> <end-line>   print the file without the block
strip_block() {
  awk -v s="$2" -v e="$3" '$0==s{skip=1; next} skip&&$0==e{skip=0; next} !skip{print}' "$1"
}

# install_block <file> <start> <end> <block-text>
install_block() {
  local file=$1 start=$2 end=$3 block=$4 tmp
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    [[ -f "${file}.kbook-backup" ]] || cp -p "$file" "${file}.kbook-backup"
    strip_block "$file" "$start" "$end" > "$tmp"
  fi
  printf '%s\n' "$block" >> "$tmp"
  mkdir -p "$(dirname "$file")"
  cat "$tmp" > "$file"
  rm -f "$tmp"
  echo "updated ${file}"
}

if ((print_only)); then
  echo "--- would add to ${rc}:"; block_rc
  ((do_vim)) && { echo "--- would add to ${vimrc}:"; block_vim; }
  exit 0
fi
install_block "$rc" "$start_rc" "$end_rc" "$(block_rc)"
((do_vim)) && install_block "$vimrc" "$start_vim" "$end_vim" "$(block_vim)"
echo "Open a new shell (or: source ${rc}) to use k, \$do, \$now and kn."
