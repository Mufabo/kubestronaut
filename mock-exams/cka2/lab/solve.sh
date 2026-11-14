#!/usr/bin/env bash
# shellcheck disable=SC2029  # variables in ssh commands are meant to expand on cp1
# Automated reference solution (used by the test loop on cp1). Human-readable
# version: solutions.md. The node fault (question 14) goes first.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_lab_cluster

C=$COURSE
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Q14
on node2 "sudo sed -i 's|clientCAFile: /etc/kubernetes/pki/ca-cert.crt|clientCAFile: /etc/kubernetes/pki/ca.crt|' ${KUBELET_CONFIG} && sudo systemctl restart kubelet"
wait_for "node2 Ready" 300 node_ready node2

# Q1: a key, a request, a certificate signed by the cluster CA, and a kubeconfig.
openssl genrsa -out "${C}/1/dev.key" 2048 2>/dev/null
openssl req -new -key "${C}/1/dev.key" -subj "/CN=dev" -out "${tmp}/dev.csr" 2>/dev/null
sudo openssl x509 -req -in "${tmp}/dev.csr" -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key \
  -CAcreateserial -CAserial "${tmp}/ca.srl" -days 30 -out "${C}/1/dev.crt" 2>/dev/null
sudo chown "$(id -u):$(id -g)" "${C}/1/dev.crt"
k="${C}/1/dev.kubeconfig"
kubectl config --kubeconfig="$k" set-cluster kbook-vm --server="https://${CP_IP}:6443" \
  --certificate-authority=/etc/kubernetes/pki/ca.crt --embed-certs=true >/dev/null
kubectl config --kubeconfig="$k" set-credentials dev --client-certificate="${C}/1/dev.crt" \
  --client-key="${C}/1/dev.key" --embed-certs=true >/dev/null
kubectl config --kubeconfig="$k" set-context dev --cluster=kbook-vm --user=dev --namespace=cka2-dev >/dev/null
kubectl config --kubeconfig="$k" use-context dev >/dev/null
kubectl -n cka2-dev create rolebinding dev-edit --clusterrole=edit --user=dev >/dev/null

# Q2
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cka2-reports-viewer
  labels:
    rbac.authorization.k8s.io/aggregate-to-view: "true"
rules:
  - apiGroups: [cka2.kbook.io]
    resources: [reports]
    verbs: [get, list, watch]
YAML

# Q3
cat > "${C}/3/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - components.yaml
patches:
  - target:
      kind: Deployment
      name: metrics-server
      namespace: kube-system
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/args/-
        value: --kubelet-insecure-tls
EOF
kubectl apply -k "${C}/3" >/dev/null

# Q4
helm -n cka2-legacy uninstall jobs >/dev/null

# Q5, Q6
kubectl -n cka2-work apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cache
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cache
  template:
    metadata:
      labels:
        app: cache
    spec:
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - topologyKey: kubernetes.io/hostname
              labelSelector:
                matchLabels:
                  app: cache
      containers:
        - name: cache
          image: nginx:1.27
YAML
kubectl -n cka2-work set resources deployment big --requests=cpu=100m,memory=64Mi >/dev/null

# Q7
on node1 "sudo tee ${STATIC_POD} >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: node-probe
  namespace: cka2-work
spec:
  containers:
    - name: probe
      image: busybox:1.36
      command: [\"sleep\", \"infinity\"]
YAML"

# Q8, Q9, Q10
dns="$(kubectl -n kube-system get service kube-dns -o jsonpath='{.spec.clusterIP}')"
kubectl -n cka2-net apply -f - >/dev/null <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: version-route
spec:
  parentRefs:
    - name: cka2-gw
  hostnames: [app.cka2.test]
  rules:
    - matches:
        - headers:
            - name: X-Version
              value: v2
      backendRefs:
        - name: app-v2
          port: 80
    - backendRefs:
        - name: app-v1
          port: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: dns-client
spec:
  dnsPolicy: None
  dnsConfig:
    nameservers: [${dns}]
    searches: [cka2-net.svc.cluster.local]
    options:
      - name: ndots
        value: "2"
  containers:
    - name: client
      image: busybox:1.36
      command: ["sleep", "infinity"]
---
apiVersion: v1
kind: Service
metadata:
  name: legacy-db
spec:
  ports:
    - port: 5432
      protocol: TCP
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: legacy-db-1
  labels:
    kubernetes.io/service-name: legacy-db
addressType: IPv4
ports:
  - port: 5432
    protocol: TCP
endpoints:
  - addresses: [10.0.0.50]
YAML

# Q11
kubectl -n cka2-locked apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
YAML

# Q12, Q13
kubectl -n cka2-data apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: reports
spec:
  storageClassName: manual
  accessModes: [ReadWriteOnce]
  selector:
    matchLabels:
      tier: reports
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: reader
spec:
  volumes:
    - name: shared
      persistentVolumeClaim:
        claimName: shared
  containers:
    - name: reader
      image: busybox:1.36
      command: ["sleep", "infinity"]
      volumeMounts:
        - name: shared
          mountPath: /data
          subPath: logs
          readOnly: true
YAML

# Q15: the cluster's CA instead of the wrong one; the credentials stay.
kubectl config --kubeconfig="${C}/15/ops.kubeconfig" set-cluster kbook-vm \
  --certificate-authority=/etc/kubernetes/pki/ca.crt --embed-certs=true >/dev/null

# Q16
kubectl -n cka2-ops logs cruncher --previous > "${C}/16/line.txt"

# Q17: the policy's selector had a typo (cilent).
kubectl -n cka2-net patch networkpolicy restrict --type=json \
  -p='[{"op":"replace","path":"/spec/ingress/0/from/0/podSelector/matchLabels","value":{"role":"client"}}]' >/dev/null

# Q18
member="$(etcdctl_k8s member list)"
awk -F', ' 'NR==1 {print $3" "$4}' <<<"$member" > "${C}/18/etcd.txt"

# Wait for everything the checks read, so the score comes from settled objects.
analysts_read() { [[ "$(kubectl auth can-i list reports.cka2.kbook.io -n cka2-team --as=amy --as-group=analysts 2>/dev/null)" == yes ]]; }
wait_for "the aggregated rules in view" 120 analysts_read
kubectl -n kube-system rollout status deployment/metrics-server --timeout=300s >/dev/null
metrics_up() { kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes >/dev/null 2>&1; }
wait_for "the metrics API" 300 metrics_up
kubectl -n cka2-work rollout status deployment/cache --timeout=300s >/dev/null
kubectl -n cka2-work rollout status deployment/big --timeout=300s >/dev/null
wait_for "static Pod node-probe-node1 Running" 300 pod_phase_is cka2-work node-probe-node1 Running
kubectl -n cka2-net wait --for=condition=Ready pod/dns-client --timeout=300s >/dev/null
kubectl -n cka2-data wait --for=condition=Ready pod/reader --timeout=300s >/dev/null
b_blocked() { ! kubectl -n cka2-locked exec a -- wget -qO- -T 2 http://b >/dev/null 2>&1; }
wait_for "the default deny in cka2-locked" 120 b_blocked
client_in() { kubectl -n cka2-net exec client -- wget -qO- -T 3 http://api >/dev/null 2>&1; }
wait_for "client to reach api" 120 client_in
