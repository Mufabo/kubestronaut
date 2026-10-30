# shellcheck shell=bash
# kubectl-exam.sh: practice-shell helpers. SOURCE this file from ~/.bashrc or
# ~/.zshrc (envs/shell/install.sh does that for you); do not execute it.
#
# The real CKA/CKAD exam hosts already provide the `k` alias and Bash
# completion; this gives you the same at home, plus two variables and a helper.
# Safe to source more than once.

alias k=kubectl

# Usage (bash):  k run web --image=nginx:1.27 $do > web.yaml
#                k delete pod web $now
# In zsh an unquoted variable is not split into words; write ${=do} / ${=now}.
export do="--dry-run=client -o yaml"
export now="--force --grace-period 0"

# kubectl edit / kubectl create -o yaml | edit open this editor.
export KUBE_EDITOR="${KUBE_EDITOR:-vim}"

# kn NAMESPACE: change the default namespace of the CURRENT context.
kn() {
  kubectl config set-context --current --namespace="${1:?usage: kn NAMESPACE}"
}

# Completion for kubectl and for the `k` alias.
# Bash needs the bash-completion package (apt install bash-completion /
# brew install bash-completion@2 with a current bash).
if command -v kubectl >/dev/null 2>&1; then
  if [ -n "${BASH_VERSION:-}" ]; then
    eval "$(kubectl completion bash 2>/dev/null)"
    complete -o default -F __start_kubectl k 2>/dev/null || true
  elif [ -n "${ZSH_VERSION:-}" ]; then
    autoload -Uz compinit 2>/dev/null && compinit 2>/dev/null
    eval "$(kubectl completion zsh 2>/dev/null)"
    compdef k=kubectl 2>/dev/null || true
  fi
fi
