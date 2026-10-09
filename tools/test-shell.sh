#!/usr/bin/env bash
# Tests for envs/shell (practice-shell helpers, vimrc, install/uninstall).
# Needs no cluster and no real kubectl (a recording stub stands in). Never
# touches your real ~/.bashrc, ~/.zshrc or ~/.vimrc: everything runs in a temp dir.
#   tools/test-shell.sh
# shellcheck disable=SC2015  # `[[ ... ]] && ok || bad`: ok and bad never fail, so this is safe
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
sh_dir="${root}/envs/shell"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
ok()   { printf 'ok    %s\n' "$1"; }
bad()  { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
skip() { printf 'skip  %s\n' "$1"; }
check() { # check <description> <command...>
  local d=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}

# A kubectl stub: records its arguments and prints a tiny completion script.
mkdir -p "${work}/bin"
cat > "${work}/bin/kubectl" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "${work}/kubectl.log"
if [[ "\$1 \$2" == "completion bash" ]]; then echo '__start_kubectl() { :; }'; fi
if [[ "\$1 \$2" == "completion zsh" ]]; then echo '#compdef kubectl'; fi
exit 0
STUB
chmod +x "${work}/bin/kubectl"
export PATH="${work}/bin:${PATH}"

# ---- kubectl-exam.sh in bash ---------------------------------------------------
probe() { env -i PATH="$PATH" HOME="$work" bash --noprofile --norc -c "$1"; }
out="$(probe "source '${sh_dir}/kubectl-exam.sh'; alias k; printf 'do=%s\nnow=%s\neditor=%s\n' \"\$do\" \"\$now\" \"\$KUBE_EDITOR\"; complete -p k")"
[[ "$out" == *"alias k='kubectl'"* ]]                         && ok "bash: k is an alias for kubectl"           || bad "bash: k is an alias for kubectl ($out)"
[[ "$out" == *"do=--dry-run=client -o yaml"* ]]               && ok "bash: \$do is set"                          || bad "bash: \$do is set"
[[ "$out" == *"now=--force --grace-period 0"* ]]              && ok "bash: \$now is set"                         || bad "bash: \$now is set"
[[ "$out" == *"editor=vim"* ]]                                && ok "bash: KUBE_EDITOR defaults to vim"          || bad "bash: KUBE_EDITOR defaults to vim"
[[ "$out" == *"-F __start_kubectl k"* ]]                      && ok "bash: completion is wired to the alias"     || bad "bash: completion is wired to the alias ($out)"
out="$(env -i PATH="$PATH" HOME="$work" KUBE_EDITOR=nano bash --noprofile --norc -c "source '${sh_dir}/kubectl-exam.sh'; echo \"\$KUBE_EDITOR\"")"
[[ "$out" == "nano" ]] && ok "bash: an existing KUBE_EDITOR is respected" || bad "bash: an existing KUBE_EDITOR is respected"
check "bash: sourcing twice is harmless" probe "source '${sh_dir}/kubectl-exam.sh'; source '${sh_dir}/kubectl-exam.sh'"
check "bash: sourcing without kubectl installed is harmless" env -i PATH="/usr/bin:/bin" HOME="$work" bash --noprofile --norc -c "source '${sh_dir}/kubectl-exam.sh'"
: > "${work}/kubectl.log"
probe "source '${sh_dir}/kubectl-exam.sh'; kn demo" >/dev/null 2>&1
[[ "$(tail -n1 "${work}/kubectl.log")" == "config set-context --current --namespace=demo" ]] && ok "kn sets the namespace of the current context" || bad "kn sets the namespace of the current context ($(tail -n1 "${work}/kubectl.log"))"
check "kn without an argument fails with usage" bash -c "! env -i PATH='$PATH' HOME='$work' bash --noprofile --norc -c \"source '${sh_dir}/kubectl-exam.sh'; kn\""

# ---- kubectl-exam.sh in zsh (only if zsh exists) ----------------------------------
if command -v zsh >/dev/null 2>&1; then
  out="$(env -i PATH="$PATH" HOME="$work" zsh -f -c "source '${sh_dir}/kubectl-exam.sh'; alias k; echo \"do=\$do\"" 2>&1)"
  [[ "$out" == *"k=kubectl"* && "$out" == *"do=--dry-run=client -o yaml"* ]] && ok "zsh: alias and variables are set" || bad "zsh: alias and variables are set ($out)"
else
  skip "zsh is not installed: the zsh path of kubectl-exam.sh is untested here"
fi

# ---- install / uninstall --------------------------------------------------------------
rc="${work}/home/bashrc"; vrc="${work}/home/vimrc"; mkdir -p "${work}/home"
printf 'export FOO=1\nalias ll="ls -l"\n' > "$rc"
printf 'set number\n' > "$vrc"
cp "$rc" "${work}/rc.orig"; cp "$vrc" "${work}/vimrc.orig"

bash "${sh_dir}/install.sh" --rc "$rc" --vimrc "$vrc" --print >/dev/null
cmp -s "$rc" "${work}/rc.orig" && cmp -s "$vrc" "${work}/vimrc.orig" && ok "install --print changes nothing" || bad "install --print changes nothing"

bash "${sh_dir}/install.sh" --rc "$rc" --vimrc "$vrc" >/dev/null 2>&1
bash "${sh_dir}/install.sh" --rc "$rc" --vimrc "$vrc" >/dev/null 2>&1
n="$(grep -c 'kbook shell setup (managed' "$rc")"; [[ "$n" == "1" ]] && ok "install twice leaves exactly one block in the rc file" || bad "install twice leaves one block (found ${n})"
n="$(grep -c 'kbook vim setup (managed' "$vrc")"; [[ "$n" == "1" ]] && ok "install twice leaves exactly one block in the vimrc" || bad "install twice leaves one block (found ${n})"
grep -q 'export FOO=1' "$rc" && grep -q 'alias ll=' "$rc" && ok "install keeps the existing rc content" || bad "install keeps the existing rc content"
[[ -f "${rc}.kbook-backup" ]] && cmp -s "${rc}.kbook-backup" "${work}/rc.orig" && ok "the backup is the ORIGINAL file (not overwritten by the 2nd install)" || bad "the backup is the original file"
grep -q "source \"${sh_dir}/kubectl-exam.sh\"" "$rc" && ok "the block sources kubectl-exam.sh by absolute path" || bad "the block sources kubectl-exam.sh by absolute path"

# the installed block really works in a fresh shell
out="$(env -i PATH="$PATH" HOME="$work" bash --noprofile --norc -c "source '$rc'; alias k")"
[[ "$out" == *"alias k='kubectl'"* ]] && ok "a fresh shell that sources the edited rc gets the alias" || bad "a fresh shell that sources the edited rc gets the alias"

bash "${sh_dir}/uninstall.sh" --rc "$rc" --vimrc "$vrc" >/dev/null 2>&1
cmp -s "$rc" "${work}/rc.orig" && ok "uninstall restores the rc file exactly" || bad "uninstall restores the rc file exactly"
cmp -s "$vrc" "${work}/vimrc.orig" && ok "uninstall restores the vimrc exactly" || bad "uninstall restores the vimrc exactly"
check "uninstall twice is harmless" bash "${sh_dir}/uninstall.sh" --rc "$rc" --vimrc "$vrc"

new_rc="${work}/home/new-bashrc"; new_vrc="${work}/home/new-vimrc"
bash "${sh_dir}/install.sh" --rc "$new_rc" --vimrc "$new_vrc" >/dev/null 2>&1
[[ -f "$new_rc" && -f "$new_vrc" ]] && ok "install creates the files if they do not exist" || bad "install creates the files if they do not exist"
bash "${sh_dir}/uninstall.sh" --rc "$new_rc" --vimrc "$new_vrc" >/dev/null 2>&1
[[ ! -e "$new_rc" && ! -e "$new_vrc" ]] && ok "uninstall deletes files that install created and are now empty" || bad "uninstall deletes files that install created"

bash "${sh_dir}/install.sh" --rc "$rc" --no-vim >/dev/null 2>&1
n="$(grep -c 'kbook vim setup' "$vrc")"; [[ "$n" == "0" ]] && ok "--no-vim leaves the vimrc alone" || bad "--no-vim leaves the vimrc alone"
bash "${sh_dir}/uninstall.sh" --rc "$rc" --no-vim >/dev/null 2>&1
check "unknown options are rejected" bash -c "! bash '${sh_dir}/install.sh' --bogus"

# ---- vimrc ---------------------------------------------------------------------------------
if command -v vim >/dev/null 2>&1; then
  if vim -Es -u "${sh_dir}/vimrc" -N '+if &expandtab && &shiftwidth==2 && &tabstop==2 | quit | else | cquit | endif' >/dev/null 2>&1; then
    ok "vim loads the vimrc: expandtab and two-space indentation"
  else
    bad "vim loads the vimrc: expandtab and two-space indentation"
  fi
else
  skip "vim is not installed: the vimrc was not loaded by a real vim"
fi

echo
if ((failures == 0)); then echo "All shell-setup tests passed."; else echo "${failures} shell-setup test(s) failed."; exit 1; fi
