#!/usr/bin/env bash
# Smoke test for the Tier 2 VMs (envs/vagrant). Run it inside cp1, on any of
# the snapshots:   cd /kbook && make test-tier2-env
# CI cannot run VirtualBox, so this is how the environment is proven.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/lib.sh"

failures=0
ok()   { printf '%s\n' "${C_GRN}ok${C_RST}    $1"; }
bad()  { printf '%s\n' "${C_RED}FAIL${C_RST}  $1"; failures=$((failures + 1)); }
# expect <description> <command...>
expect() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

snapshot="$(tr -d '[:space:]' < "$KBOOK_SNAPSHOT_FILE" 2>/dev/null)"
case "$snapshot" in
  prereqs|cluster) want="$K8S_VERSION" ;;
  cluster-prev)    want="$K8S_PREV_VERSION" ;;
  *) die "not on a Tier 2 VM (no snapshot name in ${KBOOK_SNAPSHOT_FILE}); run this inside cp1" ;;
esac
info "snapshot ${snapshot}: expecting Kubernetes ${want}"

[[ "$(hostname)" == cp1 ]] && ok "running on cp1" || bad "running on cp1 (this is $(hostname))"
expect "the book is mounted and writable at /kbook" bash -c 'touch /kbook/.tier2-write-test && rm /kbook/.tier2-write-test'
for node in node1 node2; do
  out="$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$node" 'hostname; cat /etc/kbook/snapshot' 2>/dev/null | tr '\n' ' ')"
  [[ "$out" == "${node} ${snapshot} " ]] && ok "ssh ${node} works, and it is on the same snapshot" || bad "ssh ${node} (got: '${out}')"
done
kubeadm_v="$(kubeadm version -o short 2>/dev/null)"
[[ "$kubeadm_v" == "$want" ]] && ok "kubeadm is ${want}" || bad "kubeadm is ${want} (got '${kubeadm_v}')"
expect "containerd is running" systemctl is-active --quiet containerd
expect "swap is off" bash -c '[[ -z "$(swapon --show)" ]]'

if [[ "$snapshot" == prereqs ]]; then
  [[ ! -e /etc/kubernetes/admin.conf ]] && ok "no cluster yet (no /etc/kubernetes/admin.conf)" || bad "no cluster yet"
else
  [[ "$(kubectl config current-context 2>/dev/null)" == kbook-vm ]] && ok "kubectl context is kbook-vm" || bad "kubectl context is kbook-vm"
  # The same guard every Tier 2 lab uses.
  if (LAB_TIER=2 LAB_CONTEXT=kbook-vm LAB_CLUSTER_NAME=kbook-vm require_lab_cluster) >/dev/null 2>&1; then
    ok "require_lab_cluster accepts it (context and marker)"
  else
    bad "require_lab_cluster accepts it (context and marker)"
  fi
  nodes="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.status.nodeInfo.kubeletVersion} {.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null)"
  expected_nodes="$(printf 'cp1 %s True\nnode1 %s True\nnode2 %s True' "$want" "$want" "$want")"
  [[ "$nodes" == "$expected_nodes" ]] && ok "3 nodes Ready at ${want}" || bad "3 nodes Ready at ${want} (got: ${nodes//$'\n'/; })"

  ns=kbook-tier2-smoke
  kubectl delete namespace "$ns" --ignore-not-found --wait=true >/dev/null 2>&1
  kubectl create namespace "$ns" >/dev/null 2>&1
  # One Pod per node, so a node whose Pod network is broken cannot hide.
  for node in cp1 node1 node2; do
    kubectl -n "$ns" run "dns-${node}" --image=busybox:1.36 --restart=Never \
      --overrides="{\"spec\":{\"nodeName\":\"${node}\",\"tolerations\":[{\"operator\":\"Exists\"}]}}" \
      -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1
  done
  done_running() { [[ "$(kubectl -n "$ns" get pod "$1" -o jsonpath='{.status.phase}' 2>/dev/null)" =~ ^(Succeeded|Failed)$ ]]; }
  for node in cp1 node1 node2; do
    (wait_for "the DNS test Pod on ${node} to finish" 180 done_running "dns-${node}") || true
    [[ "$(kubectl -n "$ns" get pod "dns-${node}" -o jsonpath='{.status.phase}' 2>/dev/null)" == Succeeded ]] &&
      ok "a Pod on ${node} pulls an image, runs, and resolves cluster DNS" ||
      bad "a Pod on ${node} resolves cluster DNS ($(kubectl -n "$ns" logs "dns-${node}" 2>&1 | tail -n 2 | tr '\n' ' '))"
  done
  kubectl delete namespace "$ns" --wait=false >/dev/null 2>&1
fi

echo
if ((failures == 0)); then echo "Tier 2 environment OK (snapshot ${snapshot})."; else echo "${failures} check(s) failed."; exit 1; fi
