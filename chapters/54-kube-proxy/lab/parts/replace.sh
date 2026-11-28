# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # variables come from lab.env and common.sh; check functions are passed by name
# Part replace: turn on Cilium's kube-proxy replacement, remove kube-proxy and
# its rules, and see what a Pod's packets look like without it. Sourced by
# common.sh.

cilium_env() {
  kubectl -n kube-system get daemonset cilium \
    -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name==\"$1\")].value}" 2>/dev/null
}
# kpr_on_every_agent   one Cilium agent per node, each reporting
# KubeProxyReplacement: True
kpr_on_every_agent() {
  local pods p out
  mapfile -t pods < <(kubectl -n kube-system get pods -l k8s-app=cilium -o name 2>/dev/null)
  ((${#pods[@]} == ${#NODES[@]})) || return 1
  for p in "${pods[@]}"; do
    out="$(kubectl -n kube-system exec "$p" -c cilium-agent -- cilium-dbg status 2>/dev/null)"
    [[ "$out" =~ KubeProxyReplacement:[[:space:]]+True ]] || return 1
  done
}
no_kube_proxy_pods() { [[ -z "$(kubectl -n kube-system get pods -l k8s-app=kube-proxy -o name 2>/dev/null)" ]]; }
# no_kube_proxy_rules   no node has a chain kube-proxy created, or its nftables tables
no_kube_proxy_rules() {
  local n
  for n in "${NODES[@]}"; do
    [[ -z "$(kube_proxy_chains "$n")" ]] || return 1
    node_exec "$n" nft list table ip kube-proxy >/dev/null 2>&1 && return 1
    node_exec "$n" nft list table ip6 kube-proxy >/dev/null 2>&1 && return 1
  done
  return 0
}
shop_answers_all() { is_shop "$(from_client http://shop/hostname)" && shop_answers_everywhere; }
shop_endpoints() {
  kubectl -n "$ns" get pods -l app=shop -o jsonpath='{range .items[*]}{.status.podIP}{":8080\n"}{end}' 2>/dev/null
}
# wire_dst   the destination address:port of the SYN client sends for
# http://shop/, captured on client's own interface
wire_dst() {
  kubectl -n "$ns" exec -i client -- sh -s 2>/dev/null <<'EOS' | sed -n 's/.* > \([0-9.]*\)\.\([0-9]*\): Flags.*/\1:\2/p' | head -1
rm -f /tmp/syn /tmp/err
timeout 10 tcpdump -n -i eth0 -c 1 --immediate-mode 'tcp[tcpflags] & (tcp-syn|tcp-ack) == tcp-syn' >/tmp/syn 2>/tmp/err &
# tcpdump writes "listening on eth0" to stderr once it captures
n=0
until [ -s /tmp/err ] || [ "$n" -ge 2000000 ]; do n=$((n + 1)); done
curl -s -o /dev/null --max-time 3 http://shop/hostname
wait
cat /tmp/syn
EOS
}

part_setup() { start_part; }
part_teardown() { end_part; }

part_verify() {
  require_lab_cluster
  t1() {
    [[ "$(kubectl -n kube-system get configmap cilium-config -o jsonpath='{.data.kube-proxy-replacement}' 2>/dev/null)" == true ]] &&
      [[ "$(cilium_env KUBERNETES_SERVICE_HOST) $(cilium_env KUBERNETES_SERVICE_PORT)" == "${CLUSTER_NAME}-control-plane 6443" ]] &&
      kpr_on_every_agent
  }
  t2() {
    [[ -z "$(kubectl -n kube-system get daemonset,configmap -o name 2>/dev/null | grep -E '/kube-proxy$' || true)" ]] &&
      no_kube_proxy_pods && no_kube_proxy_rules && shop_answers_all
  }
  t3() {
    local got ep
    got="$(answer "${LAB_ANSWERS}/wire-dst")"
    [[ -n "$got" ]] || return 1
    for ep in $(shop_endpoints); do [[ "$got" == "$ep" ]] && return 0; done
    return 1
  }

  check 1 "Cilium runs with kubeProxyReplacement=true, reaches the API server at ${CLUSTER_NAME}-control-plane:6443, and every agent reports KubeProxyReplacement: True" \
    "helm upgrade cilium ... --reuse-values --set kubeProxyReplacement=true --set k8sServiceHost=... --set k8sServicePort=6443, then restart the cilium DaemonSet" t1
  check 2 "kube-proxy's DaemonSet, ConfigMap, Pods, and rules are gone from every node; shop answers client, every node, and NodePort 30054 from outside" \
    "Delete the DaemonSet and ConfigMap kube-proxy; then on every node: iptables-save | grep -v KUBE | iptables-restore (and the same with ip6tables-save/ip6tables-restore)" t2
  check 3 "${LAB_ANSWERS}/wire-dst holds the address:port client's packets for http://shop/ are sent to: one of the shop Pods, port 8080" \
    "Capture on client's own interface: kubectl -n ${ns} exec client -- tcpdump -n -i eth0 -c 1 tcp, and curl http://shop/ from a second terminal" t3
}

part_solve() {
  local n dst="" _
  # Task 1: the same chart version, with the replacement on and the API server's
  # real address (without kube-proxy, the ClusterIP 10.96.0.1 works only once
  # Cilium runs).
  helm upgrade cilium cilium --repo https://helm.cilium.io --version "$CILIUM_VERSION" \
    --namespace kube-system --reuse-values --set kubeProxyReplacement=true \
    --set k8sServiceHost="${CLUSTER_NAME}-control-plane" --set k8sServicePort=6443 \
    --wait --timeout 10m >/dev/null
  kubectl -n kube-system rollout restart daemonset cilium >/dev/null
  kubectl -n kube-system rollout status daemonset cilium --timeout=300s >/dev/null
  wait_for "every Cilium agent to report KubeProxyReplacement: True" 180 kpr_on_every_agent

  # Task 2: remove kube-proxy, wait until its Pods are gone (a running one would
  # write its rules again), then remove its rules on every node.
  kubectl -n kube-system delete daemonset kube-proxy --ignore-not-found >/dev/null
  kubectl -n kube-system delete configmap kube-proxy --ignore-not-found >/dev/null
  wait_for "the kube-proxy Pods to be gone" 120 no_kube_proxy_pods
  for n in "${NODES[@]}"; do
    node_exec "$n" sh -c 'iptables-save | grep -v KUBE | iptables-restore && ip6tables-save | grep -v KUBE | ip6tables-restore'
  done
  wait_for "no kube-proxy rules on any node" 60 no_kube_proxy_rules
  wait_for "shop to answer client, every node, and NodePort 30054" 60 shop_answers_all

  # Task 3: with socket-level load balancing, client's SYN already carries a
  # shop Pod's address (tcpdump on client's eth0 shows it).
  for _ in 1 2 3; do
    dst="$(wire_dst)"
    [[ -n "$dst" ]] && break
  done
  [[ -n "$dst" ]] || die "could not capture client's SYN"
  echo "$dst" > "${LAB_ANSWERS}/wire-dst"
}
