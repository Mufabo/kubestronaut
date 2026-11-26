#!/usr/bin/env bash
# Build the Part VI simulator on a brand-new cluster: Cilium (multi-pool IPAM,
# native routing), the CNI reference plugins, Multus, one exam context, and
# the faults the questions ask about.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
# The plugin installer from Chapter 51 (it caches the tarball in its own .state).
# shellcheck source=/dev/null
source "${here}/../../../chapters/51-multus/lab/common.sh"
require_cmd helm

rm -f "${STATE}/start"
cluster_fresh "$LAB_PROFILE"
mkdir -p "$STATE"
lab_course_reset "$COURSE" 1 2 3 4 5 6 7 8

info "installing Cilium ${CILIUM_VERSION} (multi-pool IPAM, native routing)"
helm install cilium cilium --repo https://helm.cilium.io --version "$CILIUM_VERSION" \
  --namespace kube-system \
  --set ipam.mode=multi-pool \
  --set 'ipam.operator.autoCreateCiliumPodIPPools.default.ipv4.cidrs={10.10.0.0/16}' \
  --set ipam.operator.autoCreateCiliumPodIPPools.default.ipv4.maskSize=27 \
  --set routingMode=native --set autoDirectNodeRoutes=true --set ipv4NativeRoutingCIDR=10.0.0.0/8 \
  --set egressMasqueradeInterfaces=eth0 --set cni.exclusive=false >/dev/null
kubectl -n kube-system rollout status daemonset/cilium --timeout=600s >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=300s >/dev/null
wait_for "the CiliumPodIPPool API" 180 kubectl get crd ciliumpodippools.cilium.io
# CoreDNS stays on the control plane, away from the node with the firewall fault.
kubectl -n kube-system patch deployment coredns --type=merge \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"node-role.kubernetes.io/control-plane":""}}}}}' >/dev/null
kubectl -n kube-system rollout status deployment/coredns --timeout=300s >/dev/null

install_cni_plugins "${here}/../../../chapters/51-multus/lab"
info "installing Multus ${MULTUS_VERSION}"
curl -fsSL "https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/${MULTUS_VERSION}/deployments/multus-daemonset-thick.yml" |
  sed "s|ghcr.io/k8snetworkplumbingwg/multus-cni:snapshot-thick|ghcr.io/k8snetworkplumbingwg/multus-cni:${MULTUS_VERSION}-thick|" |
  kubectl apply -f - >/dev/null
# The manifest limits the daemon to 50Mi and 100m CPU; under load (many Pods
# retrying at once) it is OOM-killed, and containerd stalls with it.
kubectl -n kube-system set resources daemonset/kube-multus-ds -c kube-multus \
  --requests=cpu=100m,memory=100Mi --limits=cpu=1,memory=512Mi >/dev/null
kubectl -n kube-system rollout status daemonset/kube-multus-ds --timeout=300s >/dev/null
multus_first() {
  local n
  for n in $(kind_nodes); do [[ "$(first_cni_conf "$n")" == 00-multus.conf ]] || return 1; done
}
wait_for "Multus's configuration on every node" 120 multus_first

# The exam context: the same cluster and user as kind-kbook.
cluster="$(kubectl config view -o "jsonpath={.contexts[?(@.name==\"kind-${CLUSTER_NAME}\")].context.cluster}")"
user="$(kubectl config view -o "jsonpath={.contexts[?(@.name==\"kind-${CLUSTER_NAME}\")].context.user}")"
kubectl config set-context "$CTX" --cluster="$cluster" --user="$user" >/dev/null

for ns in p6-core p6-red p6-batch p6-fabric p6-shop; do lab_create_ns "$ns"; done
kubectl annotate namespace p6-red ipam.cilium.io/ip-pool=red --overwrite >/dev/null
kubectl annotate namespace p6-batch ipam.cilium.io/ip-pool=small --overwrite >/dev/null

kubectl apply -f - >/dev/null <<YAML
apiVersion: cilium.io/v2alpha1
kind: CiliumPodIPPool
metadata:
  name: small
spec:
  ipv4:
    cidrs: ["10.31.0.0/27"]
    maskSize: 28
---
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: fabric
  namespace: p6-fabric
spec:
  config: |
    {"cniVersion": "1.0.0", "type": "macvlan", "master": "eth0", "mode": "bridge",
     "capabilities": {"ips": true}, "ipam": {"type": "static"}}
---
apiVersion: v1
kind: Pod
metadata:
  name: probe
  namespace: p6-core
  labels: {app: probe}
spec:
  nodeSelector: {kubernetes.io/hostname: kbook-worker}
  terminationGracePeriodSeconds: 0
  containers:
    - name: probe
      image: ${NETSHOOT_IMAGE}
      command: ["sleep", "infinity"]
---
apiVersion: v1
kind: Pod
metadata:
  name: echo
  namespace: p6-core
  labels: {app: echo}
spec:
  nodeSelector: {kubernetes.io/hostname: kbook-worker2}
  terminationGracePeriodSeconds: 0
  containers:
    - name: echo
      image: ${AGNHOST_IMAGE}
      args: ["netexec", "--http-port=8080"]
---
apiVersion: v1
kind: Service
metadata:
  name: echo
  namespace: p6-core
spec:
  selector: {app: echo}
  ports: [{port: 8080, targetPort: 8080}]
---
apiVersion: v1
kind: Pod
metadata:
  name: lookup
  namespace: p6-core
  labels: {app: lookup}
spec:
  nodeSelector: {kubernetes.io/hostname: kbook-worker}
  terminationGracePeriodSeconds: 0
  dnsPolicy: None
  dnsConfig:
    nameservers: ["10.96.0.99"]
    searches: ["p6-core.svc.cluster.local"]
  containers:
    - name: lookup
      image: ${NETSHOOT_IMAGE}
      command: ["sleep", "infinity"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: p6-red
spec:
  replicas: 2
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      terminationGracePeriodSeconds: 0
      containers:
        - name: web
          image: ${AGNHOST_IMAGE}
          args: ["netexec", "--http-port=8080"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
  namespace: p6-batch
spec:
  replicas: 36
  selector: {matchLabels: {app: worker}}
  template:
    metadata: {labels: {app: worker}}
    spec:
      terminationGracePeriodSeconds: 0
      containers:
        - name: worker
          image: ${AGNHOST_IMAGE}
          args: ["pause"]
---
apiVersion: v1
kind: Pod
metadata:
  name: collector
  namespace: p6-fabric
  annotations:
    k8s.v1.cni.cncf.io/networks: '[{"name": "fabric", "ips": ["172.18.110.4/24"]}]'
spec:
  nodeSelector: {kubernetes.io/hostname: kbook-worker}
  terminationGracePeriodSeconds: 0
  containers:
    - name: collector
      image: ${NETSHOOT_IMAGE}
      command: ["sleep", "infinity"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cart
  namespace: p6-shop
spec:
  replicas: 1
  selector: {matchLabels: {app: cart}}
  template:
    metadata: {labels: {app: cart}}
    spec:
      # On the probe's node, so that question 7's fault on kbook-worker2 cannot fail question 6.
      nodeSelector: {kubernetes.io/hostname: kbook-worker}
      terminationGracePeriodSeconds: 0
      containers:
        - name: cart
          image: ${NETSHOOT_IMAGE}
          command: ["socat", "TCP-LISTEN:9000,bind=127.0.0.1,fork,reuseaddr", "SYSTEM:echo cart-ok"]
YAML
kubectl -n p6-core wait --for=condition=Ready pod/probe pod/echo pod/lookup --timeout=300s >/dev/null
kubectl -n p6-fabric wait --for=condition=Ready pod/collector --timeout=300s >/dev/null
kubectl -n p6-shop rollout status deployment/cart --timeout=300s >/dev/null
# Wait until pool small is handed out completely (both /28 blocks), so the
# nodes' routes are settled when the exam starts.
small_full() {
  local got
  got="$(kubectl get ciliumnodes -o jsonpath='{range .items[*]}{.spec.ipam.pools.allocated}{"\n"}{end}')"
  [[ "$got" == *10.31.0.0/28* && "$got" == *10.31.0.16/28* ]] || return 1
  node_routes_have() { docker exec "$1" ip route show 2>/dev/null | grep -c '^10\.31\.0\.'; }
  local n
  for n in $(kind_nodes); do [[ "$(node_routes_have "$n")" -ge 2 ]] || return 1; done
}
wait_for "pool small to be fully allocated" 300 small_full

# The node fault (question 7): kbook-worker2 drops forwarded Pod traffic from other nodes.
node_exec kbook-worker2 iptables -I FORWARD -s 10.0.0.0/8 -d 10.0.0.0/8 -i eth0 -j DROP

date +%s > "${STATE}/start"       # the clock starts when setup ends
info "Exam ready. You have ${EXAM_MINUTES} minutes; the pass mark is ${EXAM_PASS_PERCENT}%."
info "Questions: mock-exams/part6/part6.md. Score with: make mock-score EXAM=part6"
