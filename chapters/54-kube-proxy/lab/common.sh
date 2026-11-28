# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2153  # variables come from the sourcing script and lab.env
# Shared by the Chapter 54 lab parts. Sourced by the dispatcher scripts
# (setup/verify/solve/teardown); never executed directly.
#
# Both parts start from the same thing: the `cilium` profile with kube-proxy in
# iptables mode, and in the part's namespace the Deployment shop (two test
# servers on port 8080), the Services shop (ClusterIP, port 80, port name http)
# and shop-np (NodePort 30054), and the Pod client. ch54-outside is a netshoot
# container on the kind network, outside the cluster.

OUTSIDE=ch54-outside
NODES=("${CLUSTER_NAME}-control-plane" "${CLUSTER_NAME}-worker" "${CLUSTER_NAME}-worker2")

# Select the part (run-lab.sh exports LAB_PART; default to the first part).
LAB_PART="${LAB_PART:-modes}"
case " ${LAB_PARTS} " in
  *" ${LAB_PART} "*) ;;
  *) die "unknown part '${LAB_PART}'. Available: ${LAB_PARTS}" ;;
esac
ns_var="LAB_NS_${LAB_PART}"
ns="${!ns_var}"

# ---- reading the cluster -----------------------------------------------------
# proxy_mode <node>   the mode kube-proxy on the node reports (empty if none)
proxy_mode() { node_exec "$1" curl -s --max-time 3 localhost:10249/proxyMode 2>/dev/null || true; }
# kp_config_mode   the mode in the kube-proxy ConfigMap
kp_config_mode() {
  kubectl -n kube-system get configmap kube-proxy -o jsonpath='{.data.config\.conf}' 2>/dev/null |
    sed -n 's/^mode: *"\{0,1\}\([a-z]*\)"\{0,1\} *$/\1/p'
}
cluster_ip() { kubectl -n "$ns" get service shop -o jsonpath='{.spec.clusterIP}' 2>/dev/null; }
node_ip() { kubectl get node "$1" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null; }
is_shop() { [[ "$1" == shop-* ]]; }
from_client() { kubectl -n "$ns" exec client -- curl -s --max-time 3 "$1" 2>/dev/null; }

# kube_proxy_chains <node>   the iptables chains (IPv4 and IPv6) kube-proxy
# created on the node. The kubelet's own KUBE-KUBELET-CANARY, KUBE-FIREWALL,
# and KUBE-IPTABLES-HINT do not count.
kube_proxy_chains() {
  { node_exec "$1" iptables-save; node_exec "$1" ip6tables-save; } 2>/dev/null |
    sed -n 's/^:\(KUBE-[^ ]*\) .*/\1/p' | grep -Ev '^KUBE-(KUBELET-CANARY|FIREWALL|IPTABLES-HINT)$' | sort -u || true
}

# shop_answers_everywhere   a shop Pod answers at shop's ClusterIP from every
# node's own network namespace, and at NodePort 30054 of every node from
# outside the cluster: the traffic kube-proxy (or its replacement) handles.
shop_answers_everywhere() {
  local n ip; ip="$(cluster_ip)"
  [[ -n "$ip" ]] || return 1
  for n in "${NODES[@]}"; do
    is_shop "$(node_exec "$n" curl -s --max-time 3 "http://${ip}/hostname" 2>/dev/null)" || return 1
    is_shop "$(docker exec "$OUTSIDE" curl -s --max-time 3 "http://$(node_ip "$n"):30054/hostname" 2>/dev/null)" || return 1
  done
}

# kube-proxy names its chains after a hash of the Service port, so the names
# are known in advance (pkg/proxy/iptables and pkg/proxy/nftables):
#   svc_chain <ns>/<name>:<port name><protocol>   -> KUBE-SVC-<16 characters>
#   nft_chain <ns>/<name>/<protocol>/<port name>  -> service-<8 characters>-<input>
svc_chain() { python3 -c 'import base64,hashlib,sys; print("KUBE-SVC-" + base64.b32encode(hashlib.sha256(sys.argv[1].encode()).digest()).decode()[:16])' "$1"; }
nft_chain() { python3 -c 'import base64,hashlib,sys; n=sys.argv[1]; print("service-" + base64.b32encode(hashlib.sha256(n.encode()).digest()).decode()[:8] + "-" + n)' "$1"; }

# untouched   the cluster is still as the cilium profile built it: Cilium never
# upgraded or restarted, kube-proxy never edited or restarted and in iptables
# mode on every node, and no node has rules of another kube-proxy mode.
untouched() {
  local n rev
  rev="$(helm -n kube-system list --filter '^cilium$' -o json 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["revision"])' 2>/dev/null)" || return 1
  [[ "$rev" == 1 ]] || return 1
  [[ "$(kubectl -n kube-system get daemonset cilium -o jsonpath='{.metadata.generation}' 2>/dev/null)" == 1 ]] || return 1
  [[ "$(kubectl -n kube-system get configmap cilium-config -o jsonpath='{.data.kube-proxy-replacement}' 2>/dev/null)" == false ]] || return 1
  [[ "$(kubectl -n kube-system get daemonset kube-proxy -o jsonpath='{.metadata.generation}' 2>/dev/null)" == 1 ]] || return 1
  [[ "$(kp_config_mode)" == iptables ]] || return 1
  for n in "${NODES[@]}"; do
    [[ "$(proxy_mode "$n")" == iptables ]] || return 1
    [[ " $(kube_proxy_chains "$n" | xargs) " == *" KUBE-SERVICES "* ]] || return 1
    node_exec "$n" nft list table ip kube-proxy >/dev/null 2>&1 && return 1
    node_exec "$n" ip link show kube-ipvs0 >/dev/null 2>&1 && return 1
  done
  return 0
}

# ---- setup and teardown --------------------------------------------------------
start_part() {
  local n
  require_cmd helm
  docker rm -f "$OUTSIDE" >/dev/null 2>&1 || true
  cluster_require "$LAB_PROFILE"
  if untouched; then
    info "kube-proxy and Cilium are untouched on this cluster; reusing it"
  else
    info "building a new cluster (this lab changes kube-proxy and Cilium on every node)"
    cluster_fresh "$LAB_PROFILE"
  fi
  for n in "$LAB_NS_modes" "$LAB_NS_replace"; do lab_teardown_ns "$n"; done
  lab_create_ns "$ns"
  lab_course_reset "$LAB_ANSWERS" .

  kubectl -n "$ns" apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop
spec:
  replicas: 2
  selector:
    matchLabels: {app: shop}
  template:
    metadata:
      labels: {app: shop}
    spec:
      terminationGracePeriodSeconds: 0
      containers:
        - name: shop
          image: ${AGNHOST_IMAGE}
          args: ["netexec", "--http-port=8080"]
          ports: [{name: http, containerPort: 8080}]
          readinessProbe:
            httpGet: {path: /, port: 8080}
            periodSeconds: 2
---
apiVersion: v1
kind: Service
metadata:
  name: shop
spec:
  selector: {app: shop}
  ports:
    - name: http
      port: 80
      targetPort: http
---
apiVersion: v1
kind: Service
metadata:
  name: shop-np
spec:
  type: NodePort
  selector: {app: shop}
  ports:
    - port: 80
      targetPort: http
      nodePort: 30054
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  labels: {app: client}
spec:
  terminationGracePeriodSeconds: 0
  containers:
    - name: client
      image: ${NETSHOOT_IMAGE}
      command: ["sleep", "infinity"]
YAML
  docker run -d --name "$OUTSIDE" --label kubestronaut.io/lab=outside --network kind \
    "$NETSHOOT_IMAGE" sleep infinity >/dev/null
  kubectl -n "$ns" rollout status deployment/shop --timeout=180s >/dev/null
  kubectl -n "$ns" wait --for=condition=Ready pod/client --timeout=180s >/dev/null
  wait_for "shop to answer through kube-proxy on every node" 120 shop_answers_everywhere
  info "Lab ready (part ${LAB_PART}). Nodes: docker exec -it ${CLUSTER_NAME}-worker bash"
  info "Test from inside with kubectl -n ${ns} exec client -- curl ..., from outside with docker exec ${OUTSIDE} curl ..."
}

# end_part   remove what the part added; a cluster whose kube-proxy or Cilium
# was changed is deleted, so the next lab starts from a clean one
end_part() {
  docker rm -f "$OUTSIDE" >/dev/null 2>&1 || true
  lab_course_remove "$LAB_ANSWERS"
  [[ -n "$(kind_nodes)" ]] || return 0
  require_lab_cluster
  if untouched; then
    lab_teardown_ns "$ns"
  else
    bash "${BOOK_ROOT}/tools/cluster.sh" down
    info "this lab changed kube-proxy or Cilium, so the cluster is gone; make cluster builds the default one again (or the next lab builds its own profile)"
  fi
}

# shellcheck source=/dev/null
source "${here}/parts/${LAB_PART}.sh"
