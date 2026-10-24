#!/usr/bin/env bash
# Automated reference solution (used by the test loop on cp1). Human-readable
# version: solutions.md. The two faults (questions 14 and 15) go first.
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

# Q14
on node1 "sudo systemctl enable --now containerd" >/dev/null 2>&1
wait_for "node1 Ready" 300 node_ready node1

# Q15: fix the path, then recreate the static Pod so it does not wait out its back-off.
sudo sed -i 's|/etc/kubernetes/schedular.conf|/etc/kubernetes/scheduler.conf|' "$SCHED_CONFIG"
sudo mv "$SCHED_MANIFEST" "${STATE}/cka-scheduler.yaml"
mirror_gone() { ! kubectl -n cka-ops get pod cka-scheduler-cp1 >/dev/null 2>&1; }
wait_for "the old cka-scheduler Pod to go" 180 mirror_gone
sudo mv "${STATE}/cka-scheduler.yaml" "$SCHED_MANIFEST"

# Q1
csr_b64="$(base64 -w0 < "${C}/1/jane.csr")"
kubectl apply -f - >/dev/null <<YAML
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: jane
spec:
  request: ${csr_b64}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages: [client auth]
YAML
kubectl certificate approve jane >/dev/null
csr_issued() { [[ -n "$(kubectl get csr jane -o jsonpath='{.status.certificate}' 2>/dev/null)" ]]; }
wait_for "jane's certificate" 60 csr_issued
kubectl get csr jane -o jsonpath='{.status.certificate}' | base64 -d > "${C}/1/jane.crt"
kubectl -n cka-team create role pod-reader --verb=get,list,watch --resource=pods >/dev/null
kubectl -n cka-team create rolebinding jane-pods --role=pod-reader --user=jane >/dev/null

# Q2
printf 'replicaCount: 2\nservice:\n  type: NodePort\n' > "${C}/2/values.yaml"
helm install edge "${C}/2/chart" -n cka-infra --create-namespace -f "${C}/2/values.yaml" --wait --timeout 300s >/dev/null

# Q3: renew, then restart the API server's container; the kubelet starts it again.
sudo kubeadm certs renew apiserver >/dev/null
sudo crictl --timeout 120s stop "$(sudo crictl ps --name kube-apiserver -q)" >/dev/null
serves_new() {
  [[ "$(served_apiserver_serial)" == "$(sudo openssl x509 -noout -serial -in /etc/kubernetes/pki/apiserver.crt)" ]] &&
    kubectl get --raw /readyz >/dev/null 2>&1
}
wait_for "the API server to serve the renewed certificate" 300 serves_new

# Q4
cri="$(on node1 "sudo sed -n 's/^containerRuntimeEndpoint: *//p' /var/lib/kubelet/config.yaml")"
cni="$(on node1 "sudo ls /etc/cni/net.d" | grep -E '\.conf(list)?$' | LC_ALL=C sort)"
printf '%s\n%s\n' "$cri" "${cni%%$'\n'*}" > "${C}/4/interfaces.txt"

# Q5
kubectl create priorityclass cka-high --value=100000 >/dev/null
kubectl label node node2 tier=compute --overwrite >/dev/null
kubectl -n cka-work apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: analytics
spec:
  replicas: 2
  selector:
    matchLabels:
      app: analytics
  template:
    metadata:
      labels:
        app: analytics
    spec:
      priorityClassName: cka-high
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: tier
                    operator: In
                    values: [compute]
      containers:
        - name: analytics
          image: nginx:1.27
YAML

# Q6
kubectl -n cka-work autoscale deployment api --min=2 --max=6 --cpu=50% >/dev/null
kubectl -n cka-work patch hpa api --type=merge -p '{"spec":{"behavior":{"scaleDown":{"stabilizationWindowSeconds":60}}}}' >/dev/null

# Q7
kubectl -n cka-work rollout undo deployment/portal --to-revision=1 >/dev/null

# Q8
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-route
  namespace: cka-net
spec:
  parentRefs:
    - name: cka-gw
  hostnames: [api.cka.test]
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /v1
      backendRefs:
        - name: api
          port: 8080
          weight: 90
        - name: api-v2
          port: 8080
          weight: 10
YAML

# Q9
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-ingress
  namespace: cka-net
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              purpose: partners
          podSelector:
            matchLabels:
              role: client
      ports:
        - protocol: TCP
          port: 80
YAML

# Q10
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: legacy-np
  namespace: cka-net
spec:
  type: NodePort
  selector:
    app: legacy
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
YAML

# Q11: a rewrite rule ahead of the kubernetes plugin.
corefile="$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')"
# shellcheck disable=SC2001  # the indentation is captured and reused, which ${//} cannot do
corefile="$(sed 's|^\( *\)kubernetes cluster.local|\1rewrite name exact shop.cka.local legacy.cka-net.svc.cluster.local\n\1kubernetes cluster.local|' <<<"$corefile")"
kubectl -n kube-system create configmap coredns --from-literal=Corefile="$corefile" --dry-run=client -o yaml |
  kubectl apply -f - >/dev/null

# Q12
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-wait
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: fast-pv
spec:
  capacity:
    storage: 1Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-wait
  local:
    path: /srv/cka-fast
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values: [node2]
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fast
  namespace: cka-data
spec:
  storageClassName: local-wait
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 500Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: fast-writer
  namespace: cka-data
spec:
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: fast
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh", "-c", "echo ok > /data/ok; sleep infinity"]
      volumeMounts:
        - name: data
          mountPath: /data
YAML

# Q13
kubectl patch pv archive-pv -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}' >/dev/null
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: archive
  namespace: cka-data
spec:
  storageClassName: manual
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
YAML

# Q16
meters_measured() {
  local out
  out="$(kubectl -n cka-ops top pod -l app=meter --no-headers 2>/dev/null)"
  [[ "$(grep -c . <<<"$out")" == 3 ]]
}
wait_for "metrics for the meter Pods" 300 meters_measured
kubectl -n cka-ops top pod -l app=meter --sort-by=memory --no-headers | awk 'NR==1 {print $1}' > "${C}/16/pod.txt"

# Q17
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: client-egress
  namespace: cka-ops
spec:
  podSelector:
    matchLabels:
      app: client
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
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: cka-net
          podSelector:
            matchLabels:
              app: web
      ports:
        - protocol: TCP
          port: 80
YAML

# Q18
kubectl label node node2 role=infra --overwrite >/dev/null

# Wait for everything the checks read, so the score comes from settled objects.
wait_for "pod cka-scheduler-cp1 Running" 300 pod_phase_is cka-ops cka-scheduler-cp1 Running
wait_for "pod waiting Running" 300 pod_phase_is cka-ops waiting Running
kubectl -n cka-work rollout status deployment/analytics --timeout=300s >/dev/null
kubectl -n cka-work rollout status deployment/portal --timeout=300s >/dev/null
kubectl -n cka-ops rollout status deployment/infra-agent --timeout=300s >/dev/null
kubectl -n cka-data wait --for=condition=Ready pod/fast-writer --timeout=300s >/dev/null
archive_bound() { [[ "$(kubectl -n cka-data get pvc archive -o jsonpath='{.status.phase}')" == Bound ]]; }
wait_for "PVC archive Bound" 120 archive_bound
stranger_blocked() { ! kubectl -n cka-team exec stranger -- wget -qO- -T 2 http://backend.cka-net >/dev/null 2>&1; }
wait_for "the NetworkPolicy to block stranger" 120 stranger_blocked
client_reaches_web() { kubectl -n cka-ops exec client -- wget -qO- -T 3 http://web.cka-net >/dev/null 2>&1; }
wait_for "client to reach web" 120 client_reaches_web
shop_resolves() {
  local ip out
  ip="$(kubectl -n cka-net get service legacy -o jsonpath='{.spec.clusterIP}')"
  out="$(kubectl -n cka-net exec local -- nslookup shop.cka.local. 2>/dev/null)"
  grep -Eq "^Address: *${ip}$" <<<"$out"
}
wait_for "CoreDNS to resolve shop.cka.local" 240 shop_resolves
