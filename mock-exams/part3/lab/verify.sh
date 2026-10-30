#!/usr/bin/env bash
# Score the Part III simulator. Read-only. One check per question (all or
# nothing), then the weighted score against the pass mark.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_snapshot "$LAB_SNAPSHOT"
require_lab_cluster

C=$COURSE
want_pkg="${K8S_VERSION#v}-"
# jp <namespace> <resource> <jsonpath>
jp() { kubectl -n "$1" get "$2" -o "jsonpath=$3" 2>/dev/null; }
running() {
  local r
  r="$(jp "$1" "pod/$2" '{.status.containerStatuses[*].ready}')" || return 1
  [[ "$(jp "$1" "pod/$2" '{.status.phase}')" == Running && -n "$r" && "$r" != *false* ]]
}
# fetch <namespace> <pod> <url>   succeeds when the Pod can GET the URL within 3 seconds
fetch() { kubectl -n "$1" exec "$2" -- wget -q -T 3 -O - "$3" 2>/dev/null; }
word() { tr -d '[:space:]' < "$1" 2>/dev/null; }
can() { [[ "$(kubectl auth can-i "$@" 2>/dev/null)" == yes ]]; }

# ---- Q1 a Pod on the control plane node ----------------------------------------
q1() {
  running p3-sched fast || return 1
  [[ "$(jp p3-sched pod/fast '{.spec.containers[0].image}')" == nginx:1.27 ]] || return 1
  [[ "$(jp p3-sched pod/fast '{.spec.nodeName}')" == cp1 ]] || return 1
  [[ "$(jp p3-sched pod/fast '{.spec.nodeSelector.kubernetes\.io/hostname}')" == cp1 ]] || return 1
  [[ "$(jp p3-sched pod/fast '{.spec.tolerations[?(@.key=="node-role.kubernetes.io/control-plane")].effect}')" == *NoSchedule* ]]
}

# ---- Q2 a static Pod on cp1 -------------------------------------------------------
q2() {
  running p3-ops ops-monitor-cp1 || return 1
  [[ "$(jp p3-ops pod/ops-monitor-cp1 '{.metadata.ownerReferences[0].kind}')" == Node ]] || return 1
  [[ "$(jp p3-ops pod/ops-monitor-cp1 '{.spec.containers[0].image}')" == busybox:1.36 ]]
}

# ---- Q3 a join command for a new worker ---------------------------------------------
q3() {
  local line token hash want_hash
  line="$(tr -d '\\\n' < "${C}/3/join.sh" 2>/dev/null | tr -s ' ')" || return 1
  [[ "$line" =~ kubeadm\ join\ ${CP_IP}:6443\ --token\ ([a-z0-9]{6}\.[a-z0-9]{16})\ --discovery-token-ca-cert-hash\ sha256:([0-9a-f]{64}) ]] || return 1
  token="${BASH_REMATCH[1]}" hash="${BASH_REMATCH[2]}"
  sudo kubeadm token list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -qx "$token" || return 1
  want_hash="$(sudo openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | sha256sum | cut -d' ' -f1)"
  [[ "$hash" == "$want_hash" ]]
}

# ---- Q4 the control plane upgrade --------------------------------------------------
q4() {
  local images versions held p
  [[ "$(jp kube-system configmap/kubeadm-config '{.data.ClusterConfiguration}')" == *"kubernetesVersion: ${K8S_VERSION}"* ]] || return 1
  images="$(kubectl -n kube-system get pods -l 'component in (kube-apiserver,kube-controller-manager,kube-scheduler)' \
    -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}')" || return 1
  [[ "$(grep -c ":${K8S_VERSION}$" <<<"$images")" == 3 ]] || return 1
  # shellcheck disable=SC2016  # dpkg-query's format, not shell variables
  versions="$(dpkg-query -W -f='${Package} ${Version}\n' kubeadm kubelet kubectl)" || return 1
  held="$(apt-mark showhold)" || return 1
  for p in kubeadm kubelet kubectl; do
    grep -q "^${p} ${want_pkg}" <<<"$versions" || return 1
    grep -qx "$p" <<<"$held" || return 1
  done
  [[ "$(kubectl get node cp1 -o jsonpath='{.status.nodeInfo.kubeletVersion}')" == "$K8S_VERSION" ]] || return 1
  [[ "$(kubectl get node cp1 -o jsonpath='{.spec.unschedulable}')" != true ]]
}

# ---- Q5 the Deployment that cannot pull its image ------------------------------------
q5() {
  [[ "$(jp p3-apps deployment/report '{.spec.template.spec.containers[0].image}')" == nginx:1.27 ]] || return 1
  [[ "$(jp p3-apps deployment/report '{.status.availableReplicas}')" == 1 ]]
}

# ---- Q6 an etcd backup -------------------------------------------------------------
q6() {
  local rev since
  sudo test -f "${C}/6/etcd.db" || return 1
  rev="$(sudo etcdutl snapshot status "${C}/6/etcd.db" -w json 2>/dev/null | sed -nE 's/.*"revision":([0-9]+).*/\1/p')"
  # shellcheck disable=SC2153  # STATE comes from common.sh
  since="$(cat "${STATE}/marker-rv" 2>/dev/null)"
  [[ -n "$rev" && -n "$since" ]] && ((rev >= since))
}

# ---- Q7 a NetworkPolicy, tested with traffic --------------------------------------------
q7() {
  kubectl -n p3-net get networkpolicy db-allow >/dev/null 2>&1 || return 1
  [[ "$(fetch p3-net api http://db)" == *nginx* ]] || return 1
  [[ "$(fetch p3-net other http://db)" != *nginx* ]]
}

# ---- Q8 the Service network --------------------------------------------------------
q8() {
  local want
  want="$(sudo grep -oE -- '--service-cluster-ip-range=[^ ]+' /etc/kubernetes/manifests/kube-apiserver.yaml | cut -d= -f2)"
  [[ -n "$want" && "$(word "${C}/8/service-cidr.txt")" == "$want" ]]
}

# ---- Q9 a static PersistentVolume and its claim -----------------------------------------
q9() {
  [[ "$(kubectl get pv logs-pv -o jsonpath='{.spec.persistentVolumeReclaimPolicy} {.spec.storageClassName} {.spec.hostPath.path} {.spec.capacity.storage} {.spec.accessModes[0]}' 2>/dev/null)" == "Retain manual /srv/p3-logs 1Gi ReadWriteOnce" ]] || return 1
  [[ "$(jp p3-data pvc/logs '{.status.phase} {.spec.volumeName} {.spec.resources.requests.storage}')" == "Bound logs-pv 500Mi" ]] || return 1
  running p3-data writer || return 1
  [[ "$(jp p3-data pod/writer '{.spec.volumes[?(@.persistentVolumeClaim.claimName=="logs")].name}')" != "" ]] || return 1
  [[ "$(jp p3-data pod/writer '{.spec.containers[0].volumeMounts[*].mountPath}')" == */logs* ]]
}

# ---- Q10 a ServiceAccount that manages Deployments -----------------------------------------
q10() {
  local sa=system:serviceaccount:p3-apps:deployer v
  kubectl -n p3-apps get serviceaccount deployer >/dev/null 2>&1 || return 1
  for v in get list create update; do can "$v" deployments.apps -n p3-apps --as="$sa" || return 1; done
  ! can delete deployments.apps -n p3-apps --as="$sa" &&
  ! can create deployments.apps -n default --as="$sa" &&
  ! can create pods -n p3-apps --as="$sa"
}

# ---- Q11 a user who may read nodes ------------------------------------------------------
q11() {
  can list nodes --as=auditor && can get nodes --as=auditor &&
  ! can delete nodes --as=auditor &&
  ! can list pods -A --as=auditor &&
  ! can list secrets -A --as=auditor &&
  [[ "$(kubectl get clusterrolebinding auditor-nodes -o jsonpath='{.roleRef.name}' 2>/dev/null)" == node-reader ]]
}

# ---- Q12 a custom resource ----------------------------------------------------------------
q12() {
  [[ "$(jp p3-ops backups.ops.kbook.io/nightly '{.spec.schedule}|{.spec.retain}')" == "0 2 * * *|7" ]]
}

# ---- Q13 a HorizontalPodAutoscaler -----------------------------------------------------------
q13() {
  [[ "$(kubectl -n p3-apps get hpa.v2.autoscaling web -o jsonpath='{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name} {.spec.minReplicas} {.spec.maxReplicas} {.spec.metrics[?(@.resource.name=="cpu")].resource.target.averageUtilization}' 2>/dev/null)" == "Deployment/web 2 5 60" ]]
}

# ---- Q14 the Service on the wrong port ---------------------------------------------------
q14() {
  [[ "$(jp p3-apps service/shop '{.spec.ports[0].port}')" == 80 ]] || return 1
  [[ "$(fetch p3-apps probe http://shop)" == *"Welcome to nginx"* ]]
}

# ---- Q15 the kubelet on node2 ----------------------------------------------------------------
q15() {
  local state exec
  node_ready node2 || return 1
  state="$(on node2 'systemctl is-active kubelet; systemctl is-enabled kubelet' 2>/dev/null)"
  [[ "$state" == $'active\nenabled' ]] || return 1
  exec="$(on node2 "grep '^ExecStart=/' ${DROPIN}" 2>/dev/null)"
  [[ "$exec" == "ExecStart=/usr/bin/kubelet "* ]]
}

# ---- Q16 the etcd CA's expiry -------------------------------------------------------------
q16() {
  local want
  want="$(sudo openssl x509 -enddate -noout -in /etc/kubernetes/pki/etcd/ca.crt | cut -d= -f2)"
  [[ -n "$want" && "$(sed -e 's/^notAfter=//' -e 's/[[:space:]]*$//' "${C}/16/etcd-ca-expiry.txt" 2>/dev/null)" == "$want" ]]
}

check_weighted 1 6 "(p3-sched) Pod fast (nginx:1.27) runs on cp1, through a nodeSelector and a control-plane toleration" \
  "nodeSelector kubernetes.io/hostname: cp1, plus a toleration for node-role.kubernetes.io/control-plane:NoSchedule" q1
check_weighted 2 6 "(p3-ops) static Pod ops-monitor (busybox:1.36) runs on cp1" \
  "a manifest in /etc/kubernetes/manifests on cp1, with namespace p3-ops; the mirror Pod is ops-monitor-cp1" q2
check_weighted 3 5 "${C}/3/join.sh holds a working kubeadm join command (valid token and CA hash)" \
  "sudo kubeadm token create --print-join-command" q3
check_weighted 4 12 "control plane, cp1's kubelet and kubectl at ${K8S_VERSION}, packages held, cp1 schedulable" \
  "Chapter 19: repository, kubeadm, kubeadm upgrade apply ${K8S_VERSION}, drain, kubelet and kubectl, uncordon" q4
check_weighted 5 6 "(p3-apps) Deployment report runs nginx:1.27, 1 available replica" \
  "kubectl -n p3-apps describe pod -l app=report: look at the image" q5
check_weighted 6 7 "${C}/6/etcd.db is an etcd snapshot taken during the exam" \
  "etcdctl snapshot save with the endpoint and certificates from the etcd manifest" q6
check_weighted 7 8 "(p3-net) NetworkPolicy db-allow: api reaches db on port 80, other does not" \
  "podSelector app=db, ingress from podSelector app=api, port 80" q7
check_weighted 8 4 "${C}/8/service-cidr.txt holds the cluster's Service CIDR" \
  "--service-cluster-ip-range in the API server's manifest" q8
check_weighted 9 7 "PV logs-pv (1Gi, RWO, Retain, manual, /srv/p3-logs), PVC logs (500Mi) Bound to it, Pod writer runs with it at /logs" \
  "a static PV and a claim with the same storageClassName" q9
check_weighted 10 7 "(p3-apps) ServiceAccount deployer may get, list, create, update Deployments in p3-apps, and nothing more" \
  "a Role with those verbs on deployments (apps), a RoleBinding to the ServiceAccount" q10
check_weighted 11 5 "user auditor may get and list nodes (ClusterRole node-reader, ClusterRoleBinding auditor-nodes), and nothing more" \
  "kubectl create clusterrole node-reader --verb=get,list --resource=nodes" q11
check_weighted 12 5 "(p3-ops) Backup nightly: schedule 0 2 * * *, retain 7" \
  "kubectl explain backup.spec" q12
check_weighted 13 5 "(p3-apps) HPA web: Deployment web, 2 to 5 replicas, 60% CPU" \
  "kubectl autoscale deployment web --min=2 --max=5 --cpu=60%" q13
check_weighted 14 6 "(p3-apps) Service shop on port 80 serves the nginx welcome page" \
  "compare the Service's targetPort with the Pod's containerPort" q14
check_weighted 15 7 "node2 is Ready; its kubelet runs from /usr/bin/kubelet and is enabled" \
  "ssh node2; systemctl status kubelet; systemctl cat kubelet; daemon-reload after editing the drop-in" q15
check_weighted 16 4 "${C}/16/etcd-ca-expiry.txt holds the expiry date of the etcd CA" \
  "openssl x509 -enddate -noout -in /etc/kubernetes/pki/etcd/ca.crt" q16

echo
report_elapsed "${STATE}/start" "$EXAM_MINUTES"
KBOOK_PASS_PERCENT=$EXAM_PASS_PERCENT finish_checks
