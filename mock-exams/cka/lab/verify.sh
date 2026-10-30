#!/usr/bin/env bash
# Score the CKA simulator. Read-only. One check per question (all or nothing),
# then the weighted score against the pass mark.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_lab_cluster

C=$COURSE
# jp <namespace> <resource> <jsonpath>
jp() { kubectl -n "$1" get "$2" -o "jsonpath=$3" 2>/dev/null; }
# running <namespace> <pod>: the Pod is Running and every container is ready
running() {
  local r
  r="$(jp "$1" "pod/$2" '{.status.containerStatuses[*].ready}')" || return 1
  [[ "$(jp "$1" "pod/$2" '{.status.phase}')" == Running && -n "$r" && "$r" != *false* ]]
}
# reach <namespace> <pod> <host>   an HTTP GET from the Pod succeeds within 3 seconds
reach() { kubectl -n "$1" exec "$2" -- wget -qO- -T 3 "http://$3" >/dev/null 2>&1; }
# fingerprint <PEM text on stdin>
fingerprint() { openssl x509 -noout -fingerprint -sha256 2>/dev/null; }

# ---- Q1 A user certificate and its permissions -----------------------------------------
q1() {
  local issued file
  [[ "$(kubectl get csr jane -o jsonpath='{.spec.signerName}' 2>/dev/null)" == kubernetes.io/kube-apiserver-client ]] || return 1
  [[ "$(kubectl get csr jane -o jsonpath='{.status.conditions[?(@.type=="Approved")].status}' 2>/dev/null)" == True ]] || return 1
  [[ -f "${C}/1/jane.crt" ]] || return 1
  issued="$(kubectl get csr jane -o jsonpath='{.status.certificate}' 2>/dev/null | base64 -d 2>/dev/null | fingerprint)"
  file="$(fingerprint < "${C}/1/jane.crt")"
  [[ -n "$issued" && "$issued" == "$file" ]] || return 1
  [[ "$(jp cka-team rolebinding/jane-pods '{.roleRef.kind}/{.roleRef.name}')" == Role/pod-reader ]] || return 1
  [[ "$(kubectl auth can-i list pods -n cka-team --as=jane 2>/dev/null)" == yes ]] || return 1
  [[ "$(kubectl auth can-i delete pods -n cka-team --as=jane 2>/dev/null)" == no ]] || return 1
  [[ "$(kubectl auth can-i list pods -n cka-work --as=jane 2>/dev/null)" == no ]]
}

# ---- Q2 A component installed with Helm ---------------------------------------------------
q2() {
  local out values
  out="$(helm -n cka-infra status edge 2>/dev/null)" || return 1
  grep -Fq "STATUS: deployed" <<<"$out" || return 1
  grep -Eq '^replicaCount: *2$' "${C}/2/values.yaml" 2>/dev/null || return 1
  values="$(helm -n cka-infra get values edge -o json 2>/dev/null)" || return 1
  grep -Fq '"replicaCount":2' <<<"$values" || return 1
  grep -Fq '"type":"NodePort"' <<<"$values" || return 1
  [[ "$(jp cka-infra service/edge '{.spec.type}')" == NodePort ]] || return 1
  [[ "$(jp cka-infra deployment/edge '{.status.readyReplicas}')" == 2 ]]
}

# ---- Q3 Renew the API server certificate ----------------------------------------------
q3() {
  local before file served
  before="$(cat "${STATE}/apiserver-serial" 2>/dev/null)"
  file="$(sudo openssl x509 -noout -serial -in /etc/kubernetes/pki/apiserver.crt 2>/dev/null)"
  served="$(served_apiserver_serial)"
  [[ -n "$before" && -n "$file" && "$file" != "$before" && "$served" == "$file" ]]
}

# ---- Q4 Extension interfaces on node1 ----------------------------------------------------
q4() {
  local cri cni
  cri="$(on node1 "sudo sed -n 's/^containerRuntimeEndpoint: *//p' /var/lib/kubelet/config.yaml" 2>/dev/null)"
  cni="$(on node1 "sudo ls /etc/cni/net.d" 2>/dev/null | grep -E '\.conf(list)?$' | LC_ALL=C sort)"
  cni="${cni%%$'\n'*}"
  [[ -n "$cri" && -n "$cni" && -f "${C}/4/interfaces.txt" ]] || return 1
  [[ "$(cat "${C}/4/interfaces.txt")" == "${cri}"$'\n'"${cni}" ]]
}

# ---- Q5 Node affinity and priority -------------------------------------------------------
q5() {
  local a='{.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0]' nodes n
  [[ "$(kubectl get priorityclass cka-high -o jsonpath='{.value}' 2>/dev/null)" == 100000 ]] || return 1
  [[ "$(kubectl get node node2 -o jsonpath='{.metadata.labels.tier}' 2>/dev/null)" == compute ]] || return 1
  [[ "$(jp cka-work deployment/analytics "${a}.key}/${a}.operator}/${a}.values[*]}")" == tier/In/compute ]] || return 1
  [[ "$(jp cka-work deployment/analytics '{.spec.template.spec.priorityClassName}/{.spec.replicas}/{.status.readyReplicas}')" == cka-high/2/2 ]] || return 1
  nodes="$(kubectl -n cka-work get pods -l app=analytics -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null)"
  [[ -n "$nodes" ]] || return 1
  for n in $nodes; do
    [[ "$(kubectl get node "$n" -o jsonpath='{.metadata.labels.tier}' 2>/dev/null)" == compute ]] || return 1
  done
}

# ---- Q6 Autoscaling -------------------------------------------------------------------------
q6() {
  [[ "$(jp cka-work hpa/api '{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}/{.spec.minReplicas}/{.spec.maxReplicas}')" == Deployment/api/2/6 ]] || return 1
  [[ "$(jp cka-work hpa/api '{.spec.metrics[0].resource.name}/{.spec.metrics[0].resource.target.averageUtilization}')" == cpu/50 ]] || return 1
  [[ "$(jp cka-work hpa/api '{.spec.behavior.scaleDown.stabilizationWindowSeconds}')" == 60 ]]
}

# ---- Q7 Roll back to the first image --------------------------------------------------------
q7() {
  [[ "$(jp cka-work deployment/portal '{.spec.template.spec.containers[0].image}/{.spec.replicas}/{.status.replicas}/{.status.updatedReplicas}/{.status.readyReplicas}')" == nginx:1.25/2/2/2/2 ]]
}

# ---- Q8 HTTPRoute with a weighted split ----------------------------------------------------
q8() {
  local r=httproute/api-route backends
  [[ "$(jp cka-net "$r" '{.spec.parentRefs[0].name}/{.spec.hostnames[*]}')" == cka-gw/api.cka.test ]] || return 1
  [[ "$(jp cka-net "$r" '{.spec.rules[0].matches[0].path.type}/{.spec.rules[0].matches[0].path.value}')" == PathPrefix//v1 ]] || return 1
  backends="$(jp cka-net "$r" '{range .spec.rules[0].backendRefs[*]}{.name}:{.port}:{.weight}{"\n"}{end}' | LC_ALL=C sort)"
  [[ "$backends" == $'api-v2:8080:10\napi:8080:90' ]]
}

# ---- Q9 Ingress from another Namespace ------------------------------------------------------
q9() {
  [[ "$(jp cka-net networkpolicy/backend-ingress '{.spec.podSelector.matchLabels.app}')" == backend ]] || return 1
  [[ "$(jp cka-net networkpolicy/backend-ingress '{.spec.ingress[*].ports[*].port}')" == 80 ]] || return 1
  reach cka-team caller backend.cka-net || return 1
  reach cka-team stranger backend.cka-net && return 1
  reach cka-net local backend && return 1
  return 0
}

# ---- Q10 NodePort ---------------------------------------------------------------------------
q10() {
  local out
  [[ "$(jp cka-net service/legacy-np '{.spec.type}/{.spec.ports[0].port}/{.spec.ports[0].nodePort}')" == NodePort/80/30080 ]] || return 1
  out="$(curl -s -m 5 "http://${CP_IP}:30080" 2>/dev/null)"
  grep -q 'Welcome to nginx' <<<"$out"
}

# ---- Q11 CoreDNS --------------------------------------------------------------------------
q11() {
  local ip k8s out
  ip="$(jp cka-net service/legacy '{.spec.clusterIP}')"
  k8s="$(jp default service/kubernetes '{.spec.clusterIP}')"
  [[ -n "$ip" && -n "$k8s" ]] || return 1
  out="$(kubectl -n cka-net exec local -- nslookup shop.cka.local. 2>/dev/null)"
  grep -Eq "^Address: *${ip}$" <<<"$out" || return 1
  out="$(kubectl -n cka-net exec local -- nslookup kubernetes.default.svc.cluster.local. 2>/dev/null)"
  grep -Eq "^Address: *${k8s}$" <<<"$out"
}

# ---- Q12 A local volume with a waiting StorageClass ------------------------------------------
q12() {
  [[ "$(kubectl get storageclass local-wait -o jsonpath='{.provisioner}/{.volumeBindingMode}/{.reclaimPolicy}' 2>/dev/null)" == kubernetes.io/no-provisioner/WaitForFirstConsumer/Retain ]] || return 1
  [[ "$(kubectl get pv fast-pv -o jsonpath='{.spec.storageClassName}/{.spec.local.path}/{.spec.capacity.storage}' 2>/dev/null)" == local-wait//srv/cka-fast/1Gi ]] || return 1
  [[ "$(jp cka-data pvc/fast '{.status.phase}/{.spec.volumeName}')" == Bound/fast-pv ]] || return 1
  running cka-data fast-writer || return 1
  [[ "$(jp cka-data pod/fast-writer '{.spec.nodeName}')" == node2 ]] || return 1
  [[ "$(on node2 'cat /srv/cka-fast/ok' 2>/dev/null)" == ok ]]
}

# ---- Q13 Keep the data ------------------------------------------------------------------------
q13() {
  [[ "$(kubectl get pv archive-pv -o jsonpath='{.spec.persistentVolumeReclaimPolicy}/{.status.phase}/{.spec.claimRef.namespace}/{.spec.claimRef.name}' 2>/dev/null)" == Retain/Bound/cka-data/archive ]] || return 1
  [[ "$(jp cka-data pvc/archive '{.status.phase}/{.spec.volumeName}')" == Bound/archive-pv ]]
}

# ---- Q14 node1 --------------------------------------------------------------------------------
q14() {
  node_ready node1 && [[ "$(on node1 'systemctl is-enabled containerd' 2>/dev/null)" == enabled ]]
}

# ---- Q15 The second scheduler -------------------------------------------------------------------
q15() {
  running cka-ops cka-scheduler-cp1 || return 1
  [[ "$(jp cka-ops pod/waiting '{.spec.schedulerName}')" == cka-scheduler ]] || return 1
  running cka-ops waiting
}

# ---- Q16 Resource usage -----------------------------------------------------------------------
q16() {
  [[ -f "${C}/16/pod.txt" && "$(cat "${C}/16/pod.txt")" == meter-b ]]
}

# ---- Q17 Egress out of a locked-down Namespace --------------------------------------------------
q17() {
  [[ "$(jp cka-ops networkpolicy/lockdown '{.spec}')" == '{"podSelector":{},"policyTypes":["Egress"]}' ]] || return 1
  reach cka-ops client web.cka-net || return 1
  reach cka-ops client legacy.cka-net && return 1
  return 0
}

# ---- Q18 A Pod that no node accepts --------------------------------------------------------------
q18() {
  [[ "$(jp cka-ops deployment/infra-agent '{.spec.template.spec.nodeSelector}')" == '{"role":"infra"}' ]] || return 1
  [[ "$(kubectl get nodes -l role=infra -o name 2>/dev/null)" == node/node2 ]] || return 1
  [[ "$(jp cka-ops deployment/infra-agent '{.status.readyReplicas}')" == 1 ]]
}

check_weighted 1 8 "(cka-team) CSR jane approved, its certificate in ${C}/1/jane.crt; jane may list Pods in cka-team (Role pod-reader, RoleBinding jane-pods) and nothing more" \
  "a CertificateSigningRequest with signerName kubernetes.io/kube-apiserver-client; kubectl certificate approve" q1
check_weighted 2 6 "(cka-infra) Helm release edge from ${C}/2/chart with ${C}/2/values.yaml: 2 ready replicas, a NodePort Service" \
  "helm install edge CHART -n cka-infra --create-namespace -f values.yaml" q2
check_weighted 3 7 "The API server's certificate is renewed, and the API server serves the new one" \
  "kubeadm certs renew apiserver, then restart the kube-apiserver static Pod" q3
check_weighted 4 4 "${C}/4/interfaces.txt names node1's container runtime endpoint and its CNI configuration file" \
  "the kubelet's config.yaml; sudo ls /etc/cni/net.d" q4
check_weighted 5 6 "(cka-work) PriorityClass cka-high; node2 labeled tier=compute; Deployment analytics with required node affinity and cka-high, 2 ready" \
  "kubectl create priorityclass; affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution" q5
check_weighted 6 4 "(cka-work) HPA api: 2 to 6 replicas at 50% CPU, scale-down stabilization 60s" \
  "kubectl autoscale, then add behavior.scaleDown.stabilizationWindowSeconds" q6
check_weighted 7 5 "(cka-work) Deployment portal runs nginx:1.25 again, rolled out" \
  "kubectl rollout history --revision=N; kubectl rollout undo --to-revision=N" q7
check_weighted 8 6 "(cka-net) HTTPRoute api-route: Gateway cka-gw, host api.cka.test, PathPrefix /v1, api 90 and api-v2 10 on port 8080" \
  "spec.parentRefs, hostnames, rules[].matches and rules[].backendRefs with weight" q8
check_weighted 9 6 "(cka-net) NetworkPolicy backend-ingress: only role=client Pods in purpose=partners Namespaces reach backend, on port 80" \
  "namespaceSelector and podSelector in the same from entry mean AND" q9
check_weighted 10 4 "(cka-net) Service legacy-np: NodePort 30080 for port 80, and it answers on cp1's address" \
  "kubectl expose deployment legacy --name=legacy-np --type=NodePort; set spec.ports[0].nodePort" q10
check_weighted 11 4 "CoreDNS resolves shop.cka.local to the Service legacy in cka-net, and other names as before" \
  "a rewrite rule in the coredns ConfigMap in kube-system" q11
check_weighted 12 7 "StorageClass local-wait, local PersistentVolume fast-pv on node2, PVC fast Bound, Pod fast-writer wrote ok" \
  "no-provisioner, WaitForFirstConsumer, Retain; a local PV needs nodeAffinity" q12
check_weighted 13 3 "PersistentVolume archive-pv has reclaim policy Retain, and PVC archive in cka-data is bound to it" \
  "kubectl patch pv archive-pv -p '{\"spec\":{\"persistentVolumeReclaimPolicy\":\"Retain\"}}'" q13
check_weighted 14 7 "node1 is Ready, and its container runtime starts at boot" \
  "ssh node1; systemctl status containerd" q14
check_weighted 15 7 "(cka-ops) The static Pod cka-scheduler runs on cp1, and it scheduled Pod waiting" \
  "kubectl -n cka-ops logs cka-scheduler-cp1 names the file it cannot read" q15
check_weighted 16 5 "${C}/16/pod.txt names the meter Pod that uses the most memory" \
  "kubectl -n cka-ops top pod -l app=meter --sort-by=memory" q16
check_weighted 17 6 "(cka-ops) Pod client reaches web in cka-net and nothing else there; lockdown unchanged" \
  "a second policy: egress to DNS in kube-system, and to app=web Pods in cka-net on port 80" q17
check_weighted 18 5 "(cka-ops) Deployment infra-agent runs on node2, the only node labeled role=infra; its nodeSelector unchanged" \
  "kubectl label node node2 role=infra" q18

echo
report_elapsed "${STATE}/start" "$EXAM_MINUTES"
KBOOK_PASS_PERCENT=$EXAM_PASS_PERCENT finish_checks
