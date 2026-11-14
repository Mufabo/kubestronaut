#!/usr/bin/env bash
# shellcheck disable=SC2029  # variables in ssh commands are meant to expand on cp1
# Score the CKA simulator, set 2. Read-only. One check per question (all or
# nothing), then the weighted score against the pass mark.
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
# reach <namespace> <pod> <url>   an HTTP GET from the Pod succeeds within 3 seconds
reach() { kubectl -n "$1" exec "$2" -- wget -qO- -T 3 "$3" >/dev/null 2>&1; }
# days_valid <PEM certificate file>   whole days between notBefore and notAfter
days_valid() {
  local s e
  s="$(openssl x509 -noout -startdate -in "$1" 2>/dev/null | cut -d= -f2)" || return 1
  e="$(openssl x509 -noout -enddate -in "$1" 2>/dev/null | cut -d= -f2)" || return 1
  echo $(( ($(date -d "$e" +%s) - $(date -d "$s" +%s)) / 86400 ))
}

# ---- Q1 A user, a certificate, and a kubeconfig ----------------------------------------
q1() {
  local k="${C}/1/dev.kubeconfig" crt="${C}/1/dev.crt" d
  [[ -f "$k" && -f "$crt" && -f "${C}/1/dev.key" ]] || return 1
  [[ "$(kubectl --kubeconfig "$k" auth whoami -o jsonpath='{.status.userInfo.username}' 2>/dev/null)" == dev ]] || return 1
  [[ "$(kubectl --kubeconfig "$k" config view --minify -o jsonpath='{.contexts[0].context.namespace}' 2>/dev/null)" == cka2-dev ]] || return 1
  kubectl --kubeconfig "$k" get pods >/dev/null 2>&1 || return 1
  [[ "$(openssl x509 -noout -subject -in "$crt" 2>/dev/null)" == *"CN = dev"* ]] || return 1
  d="$(days_valid "$crt")"
  [[ -n "$d" ]] && ((d >= 29 && d <= 31)) || return 1
  [[ "$(kubectl auth can-i create deployments -n cka2-dev --as=dev 2>/dev/null)/$(kubectl auth can-i create deployments -n default --as=dev 2>/dev/null)" == yes/no ]]
}

# ---- Q2 An aggregated ClusterRole ----------------------------------------------------------
q2() {
  [[ "$(kubectl get clusterrole cka2-reports-viewer -o jsonpath='{.metadata.labels.rbac\.authorization\.k8s\.io/aggregate-to-view}' 2>/dev/null)" == true ]] || return 1
  [[ "$(kubectl auth can-i list reports.cka2.kbook.io -n cka2-team --as=amy --as-group=analysts 2>/dev/null)" == yes ]] || return 1
  [[ "$(kubectl auth can-i watch reports.cka2.kbook.io -n cka2-team --as=amy --as-group=analysts 2>/dev/null)" == yes ]] || return 1
  [[ "$(kubectl auth can-i delete reports.cka2.kbook.io -n cka2-team --as=amy --as-group=analysts 2>/dev/null)" == no ]]
}

# ---- Q3 metrics-server with Kustomize ----------------------------------------------------------
q3() {
  [[ -f "${C}/3/kustomization.yaml" ]] || return 1
  [[ "$(jp kube-system deployment/metrics-server '{.spec.template.spec.containers[0].args}')" == *"--kubelet-insecure-tls"* ]] || return 1
  [[ "$(jp kube-system deployment/metrics-server '{.status.availableReplicas}')" == 1 ]] || return 1
  [[ "$(kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)" == True ]] || return 1
  kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes >/dev/null 2>&1
}

# ---- Q4 A failed Helm release ---------------------------------------------------------------------
q4() {
  local failed
  failed="$(helm list -A --failed -q 2>/dev/null)"
  [[ -z "$failed" ]] || return 1
  helm -n cka2-legacy status jobs >/dev/null 2>&1 && return 1
  [[ -z "$(kubectl -n cka2-legacy get deployment jobs -o name 2>/dev/null)" ]] || return 1
  [[ "$(helm -n cka2-apps status web 2>/dev/null)" == *"STATUS: deployed"* && "$(helm -n cka2-apps status api 2>/dev/null)" == *"STATUS: deployed"* ]]
}

# ---- Q5 Never two on one node ---------------------------------------------------------------------
q5() {
  local a='{.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0]' nodes
  [[ "$(jp cka2-work deployment/cache "${a}.topologyKey}|${a}.labelSelector.matchLabels.app}")" == "kubernetes.io/hostname|cache" ]] || return 1
  [[ "$(jp cka2-work deployment/cache '{.spec.replicas}/{.status.readyReplicas}|{.spec.template.spec.containers[0].image}')" == "2/2|nginx:1.27" ]] || return 1
  nodes="$(kubectl -n cka2-work get pods -l app=cache -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u | grep -c .)"
  [[ "$nodes" == 2 ]]
}

# ---- Q6 Requests that fit ---------------------------------------------------------------------------
q6() {
  local r='{.spec.template.spec.containers[0].resources.requests'
  [[ "$(jp cka2-work deployment/big "${r}.cpu}|${r}.memory}")" == "100m|64Mi" ]] || return 1
  [[ "$(jp cka2-work deployment/big '{.spec.replicas}/{.status.replicas}/{.status.readyReplicas}')" == 2/2/2 ]]
}

# ---- Q7 A static Pod on node1 ------------------------------------------------------------------------
q7() {
  running cka2-work node-probe-node1 || return 1
  [[ "$(jp cka2-work pod/node-probe-node1 '{.spec.containers[0].image}|{.spec.nodeName}')" == "busybox:1.36|node1" ]] || return 1
  on node1 "sudo test -f ${STATIC_POD}"
}

# ---- Q8 An HTTPRoute that matches a header --------------------------------------------------------------
q8() {
  local rules
  [[ "$(jp cka2-net httproute/version-route '{.spec.parentRefs[0].name}|{.spec.hostnames[*]}')" == "cka2-gw|app.cka2.test" ]] || return 1
  rules="$(jp cka2-net httproute/version-route '{range .spec.rules[*]}{.matches[0].headers[0].name}={.matches[0].headers[0].value}|{.backendRefs[0].name}:{.backendRefs[0].port}{"\n"}{end}' | LC_ALL=C sort)"
  [[ "$rules" == $'=|app-v1:80\nX-Version=v2|app-v2:80' ]]
}

# ---- Q9 A Pod with its own DNS settings ------------------------------------------------------------------
q9() {
  local dns resolv
  dns="$(jp kube-system service/kube-dns '{.spec.clusterIP}')"
  [[ "$(jp cka2-net pod/dns-client '{.spec.dnsPolicy}|{.spec.dnsConfig.nameservers[*]}|{.spec.dnsConfig.searches[*]}')" == "None|${dns}|cka2-net.svc.cluster.local" ]] || return 1
  [[ "$(jp cka2-net pod/dns-client '{.spec.dnsConfig.options[?(@.name=="ndots")].value}')" == 2 ]] || return 1
  running cka2-net dns-client || return 1
  resolv="$(kubectl -n cka2-net exec dns-client -- cat /etc/resolv.conf 2>/dev/null)"
  [[ "$resolv" == *"nameserver ${dns}"* && "$resolv" == *"ndots:2"* ]]
}

# ---- Q10 A Service without a selector --------------------------------------------------------------------
q10() {
  [[ "$(jp cka2-net service/legacy-db '{.spec.selector}|{.spec.ports[0].port}')" == "|5432" ]] || return 1
  [[ "$(kubectl -n cka2-net get endpointslices -l kubernetes.io/service-name=legacy-db -o jsonpath='{.items[*].addressType}|{.items[*].endpoints[*].addresses[*]}|{.items[*].ports[*].port}' 2>/dev/null)" == "IPv4|10.0.0.50|5432" ]]
}

# ---- Q11 Locked down, DNS allowed ------------------------------------------------------------------------
q11() {
  local out
  [[ "$(jp cka2-locked networkpolicy/default-deny '{.spec.podSelector}|{.spec.policyTypes[*]}')" == "{}|Ingress Egress" ]] || return 1
  [[ -z "$(jp cka2-locked networkpolicy/default-deny '{.spec.ingress[*]}{.spec.egress[*]}')" ]] || return 1
  reach cka2-locked a http://b && return 1
  out="$(kubectl -n cka2-locked exec a -- nslookup b.cka2-locked.svc.cluster.local 2>/dev/null)"
  grep -q "^Address: *[0-9]" <<<"$out"
}

# ---- Q12 A claim for a labeled volume ----------------------------------------------------------------------
q12() {
  [[ "$(jp cka2-data pvc/reports '{.status.phase}|{.spec.volumeName}|{.spec.selector.matchLabels.tier}|{.spec.resources.requests.storage}')" == "Bound|cka2-reports|reports|1Gi" ]]
}

# ---- Q13 Part of a claim, read-only ---------------------------------------------------------------------------
q13() {
  local vol m
  vol="$(jp cka2-data pod/reader '{.spec.volumes[?(@.persistentVolumeClaim.claimName=="shared")].name}')"
  [[ -n "$vol" ]] || return 1
  m="{.spec.containers[0].volumeMounts[?(@.name==\"${vol}\")]"
  [[ "$(jp cka2-data pod/reader "${m}.mountPath}|${m}.subPath}|${m}.readOnly}")" == "/data|logs|true" ]] || return 1
  running cka2-data reader || return 1
  [[ "$(kubectl -n cka2-data exec reader -- cat /data/app.log 2>/dev/null)" == "cka2 shared log" ]]
}

# ---- Q14 node2's kubelet --------------------------------------------------------------------------------------
q14() {
  node_ready node2 || return 1
  [[ "$(kubectl get --raw /api/v1/nodes/node2/proxy/configz 2>/dev/null)" == *'"clientCAFile":"/etc/kubernetes/pki/ca.crt"'* ]]
}

# ---- Q15 A kubeconfig with the wrong CA ---------------------------------------------------------------------------
q15() {
  local k="${C}/15/ops.kubeconfig"
  [[ -f "$k" ]] || return 1
  [[ "$(kubectl --kubeconfig "$k" config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' 2>/dev/null)" == "$(cat "${STATE}/ops-cert" 2>/dev/null)" ]] || return 1
  [[ "$(kubectl --kubeconfig "$k" auth whoami -o jsonpath='{.status.userInfo.username}' 2>/dev/null)" == ops ]] || return 1
  kubectl --kubeconfig "$k" -n cka2-ops get pods >/dev/null 2>&1
}

# ---- Q16 What the previous container said ---------------------------------------------------------------------------
q16() {
  [[ -f "${C}/16/line.txt" && "$(cat "${C}/16/line.txt")" == "fatal: token $(cat "${STATE}/token" 2>/dev/null) rejected" ]]
}

# ---- Q17 A policy with a typo -----------------------------------------------------------------------------------------
q17() {
  [[ "$(jp cka2-net networkpolicy/restrict '{.spec.podSelector.matchLabels.app}')" == api ]] || return 1
  reach cka2-net client http://api || return 1
  reach cka2-net outsider http://api && return 1
  return 0
}

# ---- Q18 The etcd member ------------------------------------------------------------------------------------------------
q18() {
  local member want
  member="$(etcdctl_k8s member list 2>/dev/null)"
  want="$(awk -F', ' 'NR==1 {print $3" "$4}' <<<"$member")"
  [[ -n "$want" && -f "${C}/18/etcd.txt" && "$(cat "${C}/18/etcd.txt")" == "$want" ]]
}

check_weighted 1 7 "(cka2-dev) ${C}/1/dev.kubeconfig authenticates as dev (certificate from the cluster CA, 30 days) with Namespace cka2-dev; dev may edit only there" \
  "openssl genrsa, req, and x509 -req with /etc/kubernetes/pki/ca.crt and ca.key; kubectl config --kubeconfig FILE set-cluster/set-credentials/set-context" q1
check_weighted 2 6 "ClusterRole cka2-reports-viewer is aggregated into view, so the group analysts can read Reports in cka2-team" \
  "the label rbac.authorization.k8s.io/aggregate-to-view: \"true\"; verbs get, list, watch" q2
check_weighted 3 7 "metrics-server from ${C}/3, installed with Kustomize and --kubelet-insecure-tls, is available and serves node metrics" \
  "kustomization.yaml with resources: [components.yaml] and a JSON 6902 patch that adds the argument; kubectl apply -k" q3
check_weighted 4 5 "No Helm release in the cluster is failed: jobs is uninstalled, web and api still deployed" \
  "helm list -A --failed" q4
check_weighted 5 5 "(cka2-work) Deployment cache: 2 ready replicas of nginx:1.27, on different nodes through required pod anti-affinity" \
  "podAntiAffinity with topologyKey kubernetes.io/hostname; a toleration lets one land on the control plane" q5
check_weighted 6 5 "(cka2-work) Deployment big requests 100m CPU and 64Mi each, and both replicas run" \
  "kubectl describe pod shows Insufficient cpu; kubectl set resources" q6
check_weighted 7 5 "(cka2-work) Static Pod node-probe (busybox:1.36) runs on node1 from ${STATIC_POD}" \
  "write the manifest into node1's staticPodPath; the mirror Pod is node-probe-node1" q7
check_weighted 8 6 "(cka2-net) HTTPRoute version-route on cka2-gw for app.cka2.test: X-Version: v2 to app-v2:80, everything else to app-v1:80" \
  "rules[].matches[].headers, and a second rule without matches" q8
check_weighted 9 5 "(cka2-net) Pod dns-client: dnsPolicy None, the cluster DNS as nameserver, search cka2-net.svc.cluster.local, ndots 2" \
  "spec.dnsConfig; kubectl -n kube-system get service kube-dns" q9
check_weighted 10 5 "(cka2-net) Service legacy-db (5432) without a selector, and an EndpointSlice that sends it to 10.0.0.50:5432" \
  "an EndpointSlice labeled kubernetes.io/service-name: legacy-db, addressType IPv4" q10
check_weighted 11 4 "(cka2-locked) NetworkPolicy default-deny blocks all traffic in and out; DNS still works" \
  "policyTypes [Ingress, Egress] with no rules, plus a policy that allows egress to kube-dns on 53" q11
check_weighted 12 5 "(cka2-data) PVC reports (1Gi, class manual) is bound to the volume labeled tier=reports" \
  "spec.selector.matchLabels in the claim" q12
check_weighted 13 5 "(cka2-data) Pod reader mounts the subdirectory logs of claim shared at /data, read-only, and reads app.log" \
  "volumeMounts with subPath: logs and readOnly: true" q13
check_weighted 14 8 "node2 is Ready, its kubelet using the cluster's client CA file" \
  "ssh node2; sudo journalctl -u kubelet -n 20 names the file it cannot read" q14
check_weighted 15 6 "${C}/15/ops.kubeconfig works for ops in cka2-ops; its credentials are unchanged" \
  "x509: certificate signed by unknown authority: the cluster's CA is /etc/kubernetes/pki/ca.crt" q15
check_weighted 16 5 "${C}/16/line.txt holds the line cruncher's previous container printed" \
  "kubectl logs --previous" q16
check_weighted 17 7 "(cka2-net) NetworkPolicy restrict lets client (role=client) reach api, and still not outsider" \
  "compare the policy's podSelector with the client's labels" q17
check_weighted 18 4 "${C}/18/etcd.txt holds the etcd member's name and peer URL, separated by a space" \
  "etcdctl member list, with the endpoint and certificates of Chapter 20" q18

echo
report_elapsed "${STATE}/start" "$EXAM_MINUTES"
KBOOK_PASS_PERCENT=$EXAM_PASS_PERCENT finish_checks
