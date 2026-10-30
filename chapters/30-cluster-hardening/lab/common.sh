# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # variables come from the sourcing script and lab.env
# Shared by setup, verify, solve, and teardown. Sourced after lib.sh and lab.env.

STATE="${here}/.state"
COMPONENTS=(kube-apiserver kube-controller-manager kube-scheduler)
KUBELET_CONFIG=/var/lib/kubelet/config.yaml

node_ready() {
  [[ "$(kubectl get node "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == True ]]
}

# The running kubelet's configuration on a node, as JSON, through the API server.
kubelet_configz() { kubectl get --raw "/api/v1/nodes/$1/proxy/configz" 2>/dev/null; }

# A control plane component's static Pod on cp1 runs with --profiling=false and is ready.
profiling_off() {
  local pod="$1-cp1" cmd ready
  cmd="$(kubectl -n kube-system get pod "$pod" -o jsonpath='{.spec.containers[0].command}' 2>/dev/null)"
  ready="$(kubectl -n kube-system get pod "$pod" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)"
  [[ "$cmd" == *'"--profiling=false"'* && "$ready" == true ]]
}

# The control plane's manifests ask for profiling to be off.
manifests_changed() { sudo grep -qs -- '--profiling=false' "${MANIFESTS}"/kube-*.yaml; }
