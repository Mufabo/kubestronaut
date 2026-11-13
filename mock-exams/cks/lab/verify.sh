#!/usr/bin/env bash
# Score the CKS simulator. Read-only. One check per question (all or nothing),
# then the weighted score against the pass mark.
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
# jp <namespace> <resource> <jsonpath>
jp() { kubectl -n "$1" get "$2" -o "jsonpath=$3" 2>/dev/null; }
# running <namespace> <pod>: the Pod is Running and every container is ready
running() {
  local r
  r="$(jp "$1" "pod/$2" '{.status.containerStatuses[*].ready}')" || return 1
  [[ "$(jp "$1" "pod/$2" '{.status.phase}')" == Running && -n "$r" && "$r" != *false* ]]
}
# ready <namespace> <deployment> <n>: n replicas, all updated and ready
ready() {
  [[ "$(jp "$1" "deployment/$2" '{.spec.replicas}/{.status.updatedReplicas}/{.status.readyReplicas}/{.status.replicas}')" == "$3/$3/$3/$3" ]]
}
# first_pod <namespace> <label selector>: a Running Pod's name
first_pod() {
  kubectl -n "$1" get pods -l "$2" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}
# reach <namespace> <pod> <ip>: an HTTP GET to port 8080 succeeds within 3 seconds
reach() { kubectl -n "$1" exec "$2" -- wget -qO- -T 3 "http://$3:8080" >/dev/null 2>&1; }
# sa_can <verb> <resource> <namespace>   what the ServiceAccount deployer may do
sa_can() { [[ "$(kubectl auth can-i "$1" "$2" -n "$3" --as=system:serviceaccount:cks-ci:deployer 2>/dev/null)" == yes ]]; }

# ---- Q1 NetworkPolicies in cks-shop ---------------------------------------------------
q1() {
  local api other
  jp cks-shop networkpolicy/default-deny '{.metadata.name}' >/dev/null || return 1
  jp cks-shop networkpolicy/api-allow '{.metadata.name}' >/dev/null || return 1
  # Behavior, not structure: frontend reaches api; other reaches nothing, and
  # nothing reaches other.
  api="$(jp cks-shop pod/api '{.status.podIP}')"; other="$(jp cks-shop pod/other '{.status.podIP}')"
  [[ -n "$api" && -n "$other" ]] || return 1
  reach cks-shop frontend "$api" || return 1
  ! reach cks-shop other "$api" || return 1
  ! reach cks-shop frontend "$other"
}

# ---- Q2 Genuine binaries ---------------------------------------------------------------------
q2() {
  local genuine sum f
  read -r genuine sum < "${STATE}/genuine" 2>/dev/null || return 1
  [[ -f "${C}/2/${genuine}" && "$(sha512sum "${C}/2/${genuine}" | cut -d' ' -f1)" == "$sum" ]] || return 1
  for f in kubeadm-a kubeadm-b kubeadm-c; do
    [[ "$f" == "$genuine" || ! -e "${C}/2/${f}" ]] || return 1
  done
}

# ---- Q3 Least privilege for deployer -----------------------------------------------------
q3() {
  ! kubectl get clusterrolebinding deployer-admin >/dev/null 2>&1 || return 1
  [[ "$(jp cks-ci rolebinding/deployer '{.roleRef.kind}/{.roleRef.name}')" == Role/deployer ]] || return 1
  local v
  for v in get list create update; do sa_can "$v" deployments.apps cks-ci || return 1; done
  ! sa_can delete deployments.apps cks-ci || return 1
  ! sa_can get secrets cks-ci || return 1
  ! sa_can create pods cks-ci || return 1
  ! sa_can create deployments.apps cks-prod
}

# ---- Q4 NodeRestriction ----------------------------------------------------------------------
q4() {
  local flags out
  flags="$(apiserver_flags)" || return 1
  grep -Eq -- '^--enable-admission-plugins=(.*,)?NodeRestriction(,.*)?$' <<<"$flags" || return 1
  out="$(on node1 "sudo kubectl --kubeconfig /etc/kubernetes/kubelet.conf label node node1 node-restriction.kubernetes.io/cks=probe --dry-run=server" 2>&1)"
  [[ "$out" == *"is not allowed to modify labels"* ]]
}

# ---- Q5 AppArmor for writer ------------------------------------------------------------------
q5() {
  local pods p
  ready cks-sys writer 2 || return 1
  pods="$(kubectl -n cks-sys get pods -l app=writer -o jsonpath='{range .items[*]}{.metadata.name}={.spec.nodeName}{"\n"}{end}' 2>/dev/null)"
  [[ "$(wc -l <<<"$pods")" -eq 2 ]] || return 1
  while IFS='=' read -r p node; do
    [[ "$node" == node2 ]] || return 1
    [[ "$(kubectl -n cks-sys exec "$p" -- cat /proc/1/attr/current 2>/dev/null)" == "${AA_PROFILE} (enforce)" ]] || return 1
  done <<<"$pods"
}

# ---- Q6 A seccomp profile on node1 -----------------------------------------------------------
q6() {
  local profile out
  [[ "$(jp cks-sys pod/tracer '{.spec.nodeName}/{.spec.containers[0].image}')" == node1/busybox:1.36 ]] || return 1
  profile="$(jp cks-sys pod/tracer '{.spec.containers[0].securityContext.seccompProfile.type}:{.spec.containers[0].securityContext.seccompProfile.localhostProfile}')"
  [[ "$profile" != : ]] || profile="$(jp cks-sys pod/tracer '{.spec.securityContext.seccompProfile.type}:{.spec.securityContext.seccompProfile.localhostProfile}')"
  [[ "$profile" == Localhost:cks/trace.json ]] || return 1
  running cks-sys tracer || return 1
  out="$(kubectl -n cks-sys exec tracer -- grep '^Seccomp:' /proc/1/status 2>/dev/null)"
  [[ "${out//[!0-9]/}" == 2 ]]
}

# ---- Q7 Pod Security restricted --------------------------------------------------------------
q7() {
  local warnings
  [[ "$(kubectl get namespace cks-pci -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)" == restricted ]] || return 1
  ready cks-pci payments 2 || return 1
  # A server dry run of the same label warns about every running Pod that breaks it.
  warnings="$(kubectl label --dry-run=server --overwrite namespace cks-pci pod-security.kubernetes.io/enforce=restricted 2>&1 >/dev/null)"
  [[ "$warnings" != *Warning* ]]
}

# ---- Q8 Encryption at rest with secretbox ----------------------------------------------------
q8() {
  sudo test -f "$ENC_CONFIG" || return 1
  [[ "$(etcd_prefix /registry/secrets/cks-pci/card-keys)" == "k8s:enc:secretbox:v1:cks-key:"* ]] || return 1
  [[ "$(jp cks-pci secret/card-keys '{.data.key}' | base64 -d 2>/dev/null)" == "$(cat "${STATE}/card-key" 2>/dev/null)" ]]
}

# ---- Q9 A sandboxed Deployment ---------------------------------------------------------------
q9() {
  local pod
  [[ "$(kubectl get runtimeclass sandboxed -o jsonpath='{.handler}' 2>/dev/null)" == runsc ]] || return 1
  [[ "$(jp cks-sbx deployment/untrusted '{.spec.template.spec.runtimeClassName}')" == sandboxed ]] || return 1
  ready cks-sbx untrusted 1 || return 1
  pod="$(first_pod cks-sbx app=untrusted)"
  [[ -n "$pod" && "$(kubectl -n cks-sbx exec "$pod" -- uname -r 2>/dev/null)" == *gvisor ]]
}

# ---- Q10 No latest images ---------------------------------------------------------------------
q10() {
  local d
  [[ "$(kubectl get validatingadmissionpolicybinding cks-no-latest -o jsonpath='{.spec.policyName}|{.spec.validationActions}' 2>/dev/null)" == 'cks-no-latest|["Deny"]' ]] || return 1
  # Server dry runs: nothing is stored, but admission runs.
  admitted() { kubectl -n "$1" create deployment "cks-probe-$RANDOM" --image="$2" --dry-run=server >/dev/null 2>&1; }
  ! admitted cks-prod nginx || return 1
  ! admitted cks-prod nginx:latest || return 1
  ! admitted cks-prod registry.k8s.io/pause || return 1
  admitted cks-prod nginx:1.27 || return 1
  admitted cks-prod registry.k8s.io/pause:3.10 || return 1
  d="$(cat "${STATE}/digest" 2>/dev/null)"
  admitted cks-prod "nginx@${d}" || return 1
  admitted cks-run nginx:latest
}

# ---- Q11 Pinned by digest ---------------------------------------------------------------------
q11() {
  local d image
  d="$(cat "${STATE}/digest" 2>/dev/null)"
  image="$(jp cks-prod deployment/cache '{.spec.template.spec.containers[0].image}')"
  [[ -n "$d" && ( "$image" == "nginx@${d}" || "$image" == "docker.io/library/nginx@${d}" ) ]] || return 1
  ready cks-prod cache 1
}

# ---- Q12 A hardened Dockerfile ----------------------------------------------------------------
q12() {
  local f="${C}/12/Dockerfile"
  [[ -f "$f" ]] || return 1
  [[ "$(grep -E '^FROM ' "$f")" == "FROM python:3.12-slim" ]] || return 1
  ! grep -q 'API_TOKEN' "$f" || return 1
  [[ "$(grep -E '^USER ' "$f" | tail -1)" == "USER appuser" ]] || return 1
  grep -Eq '^RUN .*useradd .*appuser' "$f" || return 1
  [[ "$(grep -vE '^\s*(#|$)' "$f" | tail -1)" == 'CMD ["python", "app.py"]' ]]
}

# ---- Q13 Audit logging ----------------------------------------------------------------------
q13() {
  local flags nonce
  flags="$(apiserver_flags)" || return 1
  for f in "--audit-policy-file=${AUDIT_POLICY}" "--audit-log-path=${AUDIT_LOG}" --audit-log-maxage=5 --audit-log-maxbackup=3; do
    grep -qxF -- "$f" <<<"$flags" || return 1
  done
  # Requests by users without rights: refused, but audited. A refused create
  # never reaches its body, so the object's name is not in the log; each probe
  # impersonates a user of its own, whose random name finds its events.
  nonce="cks-probe-$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  kubectl --as="${nonce}-s" -n cks-run get secret probe >/dev/null 2>&1
  kubectl --as="${nonce}-c" -n cks-prod create deployment probe --image=nginx:1.27 >/dev/null 2>&1
  kubectl --as="${nonce}-g" -n cks-prod get deployment probe >/dev/null 2>&1
  kubectl --as="${nonce}-o" -n cks-run create deployment probe --image=nginx:1.27 >/dev/null 2>&1
  events() { sudo grep -F -- "\"username\":\"$1\"" "$AUDIT_LOG" 2>/dev/null; }
  logged() {
    local out
    out="$(events "$1")"
    [[ -n "$out" && "$(wc -l <<<"$out")" -eq 1 && "$out" == *"\"level\":\"$2\""* ]]
  }
  unlogged() { [[ -z "$(events "$1")" ]]; }
  logged "${nonce}-s" Metadata || return 1
  logged "${nonce}-c" RequestResponse || return 1
  unlogged "${nonce}-g" || return 1
  unlogged "${nonce}-o"
}

# ---- Q14 The Pod Falco reports ----------------------------------------------------------------
q14() {
  local culprit s
  culprit="$(cat "${STATE}/culprit" 2>/dev/null)"
  [[ -n "$culprit" && -f "${C}/14/culprit.txt" && "$(cat "${C}/14/culprit.txt")" == "$culprit" ]] || return 1
  ! kubectl -n "${culprit%%/*}" get pod "${culprit##*/}" >/dev/null 2>&1 || return 1
  for s in "${SUSPECTS[@]}"; do
    [[ "$s" == "$culprit" ]] && continue
    running "${s%%/*}" "${s##*/}" || return 1
  done
}

# ---- Q15 An immutable web server ----------------------------------------------------------------
q15() {
  local volumes pod out
  ready cks-run site 2 || return 1
  [[ "$(jp cks-run deployment/site '{.spec.template.spec.containers[*].image}')" == httpd:2.4 ]] || return 1
  [[ "$(jp cks-run deployment/site '{.spec.template.spec.containers[*].securityContext.readOnlyRootFilesystem}')" == true ]] || return 1
  volumes="$(jp cks-run deployment/site '{range .spec.template.spec.volumes[*]}{.name}={.emptyDir}{"\n"}{end}')"
  [[ -z "$volumes" ]] || ! grep -q '=$' <<<"$volumes" || return 1
  pod="$(first_pod cks-run app=site)"
  [[ -n "$pod" ]] || return 1
  out="$(kubectl -n cks-run exec "$pod" -- touch /usr/local/apache2/htdocs/cks-probe 2>&1)" && return 1
  [[ "$out" == *"Read-only file system"* ]]
}

check_weighted 1 8 "(cks-shop) default-deny blocks all ingress; api-allow lets only frontend reach api on 8080" \
  "an empty podSelector with policyTypes [Ingress] and no rules; then a policy for app=api from app=frontend" q1
check_weighted 2 7 "${C}/2 keeps only the kubeadm binary that matches the official v1.37.0 release" \
  "sha512sum, compared with https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubeadm.sha512" q2
check_weighted 3 8 "(cks-ci) deployer: no cluster-admin; Role and RoleBinding deployer allow get, list, create, update on Deployments in cks-ci only" \
  "delete the ClusterRoleBinding; kubectl create role --verb=get,list,create,update --resource=deployments.apps" q3
check_weighted 4 7 "The API server runs with the NodeRestriction admission plugin, and it stops a kubelet setting restricted labels" \
  "--enable-admission-plugins in the API server's manifest" q4
check_weighted 5 5 "(cks-sys) Both writer Pods run on node2 under the AppArmor profile ${AA_PROFILE}" \
  "the profile's name is inside ${AA_FILE} on node2; apparmor_parser loads it" q5
check_weighted 6 5 "(cks-sys) Pod tracer runs on node1 with the Localhost seccomp profile cks/trace.json" \
  "copy ${C}/6/trace.json to ${SECCOMP_DIR}/ on node1" q6
check_weighted 7 6 "(cks-pci) The Namespace enforces restricted, and payments runs 2 ready replicas that comply" \
  "runAsNonRoot, runAsUser, seccompProfile RuntimeDefault, allowPrivilegeEscalation false, capabilities drop ALL" q7
check_weighted 8 7 "Secret card-keys in cks-pci is stored in etcd with secretbox and the key cks-key, and still reads the same" \
  "an EncryptionConfiguration in ${ENC_CONFIG}, the flag, a volume and a mount, then rewrite the Secrets" q8
check_weighted 9 7 "(cks-sbx) RuntimeClass sandboxed (handler runsc); Deployment untrusted runs on it, under gVisor" \
  "runtimeClassName in the Pod template; uname -r in the Pod" q9
check_weighted 10 7 "ValidatingAdmissionPolicy cks-no-latest denies Deployments in cks-prod whose images are untagged or :latest" \
  "a CEL expression over object.spec.template.spec.containers, and a binding with validationActions [Deny]" q10
check_weighted 11 6 "(cks-prod) Deployment cache refers to its image by the digest it runs, and is ready" \
  "the imageID in the Pod's status holds the digest" q11
check_weighted 12 7 "${C}/12/Dockerfile: pinned base python:3.12-slim, no token, runs as a non-root user" \
  "FROM, remove the ENV line, create the user and switch to it before CMD" q12
check_weighted 13 7 "Audit log ${AUDIT_LOG}: Secrets at Metadata, Deployment changes in cks-prod at RequestResponse, nothing else" \
  "a Policy with omitStages, the --audit-* flags, volumes and mounts in the API server's manifest" q13
check_weighted 14 6 "${C}/14/culprit.txt names the Pod Falco reports for /etc/sudoers, which is deleted; the others still run" \
  "on node1: sudo journalctl -u ${FALCO_UNIT}; k8s_ns_name and k8s_pod_name" q14
check_weighted 15 7 "(cks-run) Deployment site runs 2 ready httpd:2.4 replicas with a read-only root file system, writing only to emptyDir volumes" \
  "readOnlyRootFilesystem, then an emptyDir for the directory the logs name" q15

echo
report_elapsed "${STATE}/start" "$EXAM_MINUTES"
KBOOK_PASS_PERCENT=$EXAM_PASS_PERCENT finish_checks
