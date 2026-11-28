# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # variables come from lab.env and common.sh; check functions are passed by name
# Part modes: read kube-proxy's iptables rules, move kube-proxy to nftables
# mode, and read its nftables rules. Sourced by common.sh.

# nftables_everywhere   every node's kube-proxy runs in nftables mode, has
# shop's ClusterIP in its service-ips map, and has no iptables-mode chains left
nftables_everywhere() {
  local n ip map; ip="$(cluster_ip)"
  [[ -n "$ip" ]] || return 1
  for n in "${NODES[@]}"; do
    [[ "$(proxy_mode "$n")" == nftables ]] || return 1
    map="$(node_exec "$n" nft list map ip kube-proxy service-ips 2>/dev/null || true)"
    [[ "$map" == *"${ip} . tcp . 80 : goto "* ]] || return 1
    [[ -z "$(kube_proxy_chains "$n" | grep -E '^KUBE-(SVC|SEP)-' || true)" ]] || return 1
  done
}

part_setup() { start_part; }
part_teardown() { end_part; }

part_verify() {
  require_lab_cluster
  t1() { answer_is "${LAB_ANSWERS}/svc-chain" "$(svc_chain "${ns}/shop:httptcp")"; }
  t2() { [[ "$(kp_config_mode)" == nftables ]] && nftables_everywhere && shop_answers_everywhere; }
  t3() { answer_is "${LAB_ANSWERS}/nft-chain" "$(nft_chain "${ns}/shop/tcp/http")"; }

  check 1 "${LAB_ANSWERS}/svc-chain holds the name of the KUBE-SVC chain kube-proxy wrote for the Service shop" \
    "On a node: iptables -t nat -S KUBE-SERVICES | grep ${ns}/shop; the rule's comment names the Service and its port" t1
  check 2 "kube-proxy runs in nftables mode on every node (ConfigMap and /proxyMode), with shop's rules and no KUBE-SVC/KUBE-SEP chains left; shop answers from every node and on NodePort 30054" \
    "Set mode: nftables in the ConfigMap kube-proxy (kube-system), then kubectl -n kube-system rollout restart daemonset kube-proxy" t2
  check 3 "${LAB_ANSWERS}/nft-chain holds the name of the nftables chain that shop's ClusterIP leads to" \
    "On a node: nft list map ip kube-proxy service-ips; find shop's ClusterIP and the chain after goto" t3
}

part_solve() {
  local chain
  # Task 1: the KUBE-SERVICES rule for shop's ClusterIP jumps to its chain.
  chain="$(node_exec "${NODES[1]}" iptables -t nat -S KUBE-SERVICES 2>/dev/null |
    sed -n "s|.*\"${ns}/shop:http cluster IP\".* -j \(KUBE-SVC-[A-Z0-9]*\).*|\1|p")"
  # (After Task 2 the rules are gone; the name is still the same hash.)
  [[ -n "$chain" ]] || chain="$(svc_chain "${ns}/shop:httptcp")"
  echo "$chain" > "${LAB_ANSWERS}/svc-chain"

  # Task 2: change the mode in the ConfigMap, restart kube-proxy everywhere.
  kubectl -n kube-system get configmap kube-proxy -o yaml |
    sed 's/^    mode: .*$/    mode: nftables/' | kubectl replace -f - >/dev/null
  kubectl -n kube-system rollout restart daemonset kube-proxy >/dev/null
  kubectl -n kube-system rollout status daemonset kube-proxy --timeout=180s >/dev/null
  wait_for "kube-proxy in nftables mode with shop's rules on every node" 120 nftables_everywhere
  wait_for "shop to answer from every node and on NodePort 30054" 60 shop_answers_everywhere

  # Task 3: the service-ips map sends shop's ClusterIP to its service chain.
  node_exec "${NODES[1]}" nft list map ip kube-proxy service-ips |
    sed -n "s|.*goto \(service-[A-Z0-9]*-${ns}/shop/tcp/http\).*|\1|p" > "${LAB_ANSWERS}/nft-chain"
}
