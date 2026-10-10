#!/usr/bin/env bash
# Score the Part I simulator. Read-only. One check per question (all or
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
# jp <namespace> <pod> <jsonpath>
jp() { kubectl -n "$1" get pod "$2" -o "jsonpath=$3"; }
# ready <namespace> <pod>   Running, and every container is ready (not crash-looping)
ready() {
  local r
  r="$(jp "$1" "$2" '{.status.containerStatuses[*].ready}')" &&
  [[ "$(jp "$1" "$2" '{.status.phase}')" == "Running" && -n "$r" && "$r" != *false* ]]
}
# containers <namespace> <pod>   "name=image" per container, sorted, space separated
containers() {
  jp "$1" "$2" '{range .spec.containers[*]}{.name}={.image}{"\n"}{end}' | sort | tr '\n' ' ' | sed 's/ $//'
}
# label <namespace> <pod> <key>
label() { jp "$1" "$2" "{.metadata.labels.$3}"; }
# word <file>   the file's content without whitespace, lowercased
word() { tr -d '[:space:]' < "$1" | tr '[:upper:]' '[:lower:]'; }
# lines <file>   sorted, unique, trimmed, non-empty lines; a leading "pod/" is ignored
lines() { sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's#^pod/##' "$1" | grep -v '^$' | sort -u; }
# file_is <file> <expected-word>
file_is() { [[ -f "$1" && -n "$2" && "$(word "$1")" == "$2" ]]; }

# ---- Q1 contexts -----------------------------------------------------------------
q1_contexts() {
  local want
  want="$(kubectl config get-contexts -o name | sort -u)" &&
  [[ -n "$want" && -f "$C/1/contexts" && "$(lines "$C/1/contexts")" == "$want" ]]
}
q1_namespace() { file_is "$C/1/namespace" "$(ctx_field "$CTX_B" namespace)"; }

# ---- Q2 courier --------------------------------------------------------------------
q2_container() { [[ "$(containers p1-io courier)" == "courier-container=nginx:1.27" ]]; }
q2_labels() { [[ "$(label p1-io courier app)" == "courier" && "$(label p1-io courier tier)" == "edge" ]]; }
q2_port() { [[ "$(jp p1-io courier '{.spec.containers[0].ports[*].containerPort}')" == "80" ]]; }
q2_ready() { ready p1-io courier; }

# ---- Q3 ledger ---------------------------------------------------------------------
q3_ready() { ready p1-europa ledger; }
q3_command() {
  local cmd
  cmd="$(jp p1-europa ledger '{.spec.containers[0].command[*]} {.spec.containers[0].args[*]}' | tr -s ' ' | sed -e 's/^ //' -e 's/ $//')" &&
  [[ "$cmd" =~ (^|[[:space:]])sleep[[:space:]]+3600$ ]]
}
q3_kept() {
  [[ "$(containers p1-europa ledger)" == "ledger=busybox:1.36" ]] &&
  [[ "$(label p1-europa ledger app)" == "ledger" && "$(label p1-europa ledger team)" == "finance" ]] &&
  [[ "$(jp p1-europa ledger '{.metadata.annotations.owner}')" == "finance-ops" ]]
}

# ---- Q4 beacon ---------------------------------------------------------------------
q4_token() { file_is "$C/4/token" "$(cat "${STATE}/token" 2>/dev/null)"; }
q4_container() { file_is "$C/4/container" agent; }

# ---- Q5 cruncher -------------------------------------------------------------------
q5_pod() { [[ "$(containers p1-titan cruncher)" == *"=busybox:1.36" && "$(containers p1-titan cruncher)" != *" "* ]] && ready p1-titan cruncher; }
q5_requests() {
  [[ "$(jp p1-titan cruncher '{.spec.containers[0].resources.requests.cpu}')" == "50m" ]] &&
  [[ "$(jp p1-titan cruncher '{.spec.containers[0].resources.requests.memory}')" == "32Mi" ]]
}
q5_limits() {
  [[ "$(jp p1-titan cruncher '{.spec.containers[0].resources.limits.memory}')" == "64Mi" ]] &&
  [[ -z "$(jp p1-titan cruncher '{.spec.containers[0].resources.limits.cpu}')" ]]
}

# ---- Q6 migrate and importer -------------------------------------------------------
q6_spec() {
  [[ "$(containers p1-io migrate)" == *"=busybox:1.36" && "$(containers p1-io migrate)" != *" "* ]] &&
  [[ "$(jp p1-io migrate '{.spec.restartPolicy}')" == "Never" ]]
}
q6_ran() {
  [[ "$(jp p1-io migrate '{.status.phase}')" == "Failed" ]] &&
  [[ "$(jp p1-io migrate '{.status.containerStatuses[0].state.terminated.exitCode}')" == "4" ]] &&
  [[ "$(kubectl -n p1-io logs migrate)" == *"migration finished"* ]]
}
q6_code() { file_is "$C/6/exit-code" "$(jp p1-io importer '{.status.containerStatuses[0].state.terminated.exitCode}')"; }

# ---- Q7 and Q8 callisto labels -------------------------------------------------------
# rows: name|tier|env|stage|temp|protected|audit for every seeded Pod
SEED="c-web-1 c-web-2 c-db-1 c-db-2 c-cache-1 c-cache-2 c-batch-1 c-misc"
rows() {
  local all
  all="$(kubectl -n p1-callisto get pods -o jsonpath='{range .items[*]}{.metadata.name}|{.metadata.labels.tier}|{.metadata.labels.env}|{.metadata.labels.stage}|{.metadata.labels.temp}|{.metadata.labels.protected}|{.metadata.annotations.audit}{"\n"}{end}')" || return 1
  awk -F'|' -v seed="$SEED" 'BEGIN{n=split(seed,a," "); for(i=1;i<=n;i++) s[a[i]]=1} ($1 in s)' <<<"$all"
}
# every <awk-condition> : true if all 8 seeded Pods exist and each one satisfies the condition
every() { local r; r="$(rows)" && [[ "$(wc -l <<<"$r" | tr -d '[:space:]')" == "8" ]] && awk -F'|' "!($1){bad=1} END{exit bad}" <<<"$r"; }
q7_protected() { every '($2=="db" || $2=="cache") ? $6=="true" : 1'; }
q7_only()      { every '($2=="db" || $2=="cache") ? 1 : $6==""'; }
q7_audit()     { every '$3=="prod" ? $7=="q4-2026" : $7==""'; }
q8_ga() { every '($1=="c-web-1" || $1=="c-db-1" || $1=="c-batch-1") ? $4=="ga" : 1'; }
q8_others() {
  every '$1=="c-web-2" ? $4=="ga" : ($1=="c-db-2" || $1=="c-cache-2") ? $4=="alpha" : ($1=="c-cache-1" || $1=="c-misc") ? $4=="" : 1'
}
q8_temp() { every '$5==""'; }

# ---- Q9 output -----------------------------------------------------------------------
q9_pods() {
  local want
  want="$(kubectl -n p1-callisto get pods -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[*].image}{"\n"}{end}' | awk '{for(i=2;i<=NF;i++) if($i=="nginx:1.26"){print $1; break}}' | sort -u)" &&
  [[ -n "$want" && -f "$C/9/pods" && "$(lines "$C/9/pods")" == "$want" ]]
}
q9_count() {
  local want
  want="$(kubectl -n p1-callisto get pods -o jsonpath='{.items[*].spec.containers[*].name}' | wc -w | tr -d '[:space:]')" &&
  file_is "$C/9/containers" "$want"
}

# ---- Q10 gateway ---------------------------------------------------------------------
q10_file() {
  local t
  [[ -f "$C/10/gateway.yaml" ]] && t="$(<"$C/10/gateway.yaml")" &&
  [[ "$t" == *"kind: Pod"* && "$t" == *"name: gateway"* && "$t" == *"name: helper"* && "$t" == *"MODE"* ]]
}
q10_containers() {
  [[ "$(containers p1-io gateway)" == "gateway=nginx:1.27 helper=busybox:1.36" ]] &&
  [[ "$(jp p1-io gateway '{.spec.containers[?(@.name=="gateway")].env[?(@.name=="MODE")].value}')" == "edge" ]]
}
q10_ready() { [[ "$(label p1-io gateway app)" == "gateway" ]] && ready p1-io gateway; }

# ---- Q11 config objects ----------------------------------------------------------------
cm() { kubectl -n p1-europa get configmap ledger-config -o "jsonpath=$1"; }
q11_cm() { [[ "$(cm '{.data.currency}')" == "EUR" && "$(cm '{.data.rounding}')" == "half-even" ]]; }
q11_secret() {
  local u p
  u="$(kubectl -n p1-europa get secret ledger-db -o jsonpath='{.data.user}')" &&
  p="$(kubectl -n p1-europa get secret ledger-db -o jsonpath='{.data.password}')" &&
  [[ "$(printf '%s' "$u" | base64 -d)" == "ledger" && "$(printf '%s' "$p" | base64 -d)" == "l3dg3r-pw" ]]
}
q11_sa() { [[ "$(kubectl -n p1-europa get serviceaccount ledger-sa -o jsonpath='{.metadata.name}')" == "ledger-sa" ]]; }
q11_svc() {
  local s
  s="$(kubectl -n p1-europa get service ledger-svc -o jsonpath='{.spec.selector.app}|{.spec.ports[0].port}|{.spec.ports[0].targetPort}')" &&
  [[ "$s" == "ledger|8080|80" ]]
}

# ---- Q12 API discovery -------------------------------------------------------------------
q12_api() {
  local served
  file_is "$C/12/cronjob-api" "batch/v1" &&
  served="$(kubectl api-resources --api-group=batch -o name)" && grep -qx 'cronjobs.batch' <<<"$served"
}
q12_type() { [[ -f "$C/12/run-as-non-root" && "$(word "$C/12/run-as-non-root" | tr -d '<>')" == "boolean" ]]; }
q12_namespaced() {
  local cluster_scoped
  cluster_scoped="$(kubectl api-resources --namespaced=false -o name)" &&
  if grep -qx namespaces <<<"$cluster_scoped"; then file_is "$C/12/namespaced" no; else file_is "$C/12/namespaced" yes; fi
}

# ---- Q13 permissions ------------------------------------------------------------------------
SA=system:serviceaccount:p1-titan:auditor
can() { local o; o="$(kubectl auth can-i "$1" "$2" -n "$3" --as="$SA" 2>/dev/null || true)"; printf '%s' "${o:-unknown}"; }
q13_line() {
  local n=$1 verb=$2 res=$3 ns=$4 want given
  want="$(can "$verb" "$res" "$ns")" &&
  [[ "$want" == yes || "$want" == no ]] && [[ -f "$C/13/answers" ]] &&
  given="$(lines_in_order "$C/13/answers")" &&
  [[ "$(wc -l <<<"$given" | tr -d '[:space:]')" == "4" && "$(sed -n "${n}p" <<<"$given")" == "$want" ]]
}
# lines_in_order <file>   trimmed, lowercased, non-empty lines, order kept
lines_in_order() { tr '[:upper:]' '[:lower:]' < "$1" | sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$'; }

# ---- Q14 control plane --------------------------------------------------------------------------
owner_kind() { kubectl -n kube-system get "$1" "$2" -o jsonpath='{.metadata.ownerReferences[0].kind}'; }
owner_name() { kubectl -n kube-system get "$1" "$2" -o jsonpath='{.metadata.ownerReferences[0].name}'; }
q14_image() { file_is "$C/14/apiserver-image" "$(kubectl -n kube-system get pods -l component=kube-apiserver -o jsonpath='{.items[0].spec.containers[0].image}' | tr '[:upper:]' '[:lower:]')"; }
q14_proxy() {
  local pod
  pod="$(kubectl -n kube-system get pods -l k8s-app=kube-proxy -o jsonpath='{.items[0].metadata.name}')" &&
  file_is "$C/14/proxy-owner" "$(owner_kind pod "$pod" | tr '[:upper:]' '[:lower:]')"
}
q14_dns() {
  local pod kind name
  pod="$(kubectl -n kube-system get pods -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}')" &&
  kind="$(owner_kind pod "$pod")" && name="$(owner_name pod "$pod")" &&
  # Walk up one more level when a ReplicaSet sits in between.
  if [[ "$kind" == ReplicaSet ]]; then kind="$(owner_kind replicaset "$name")"; fi &&
  file_is "$C/14/dns-owner" "$(tr '[:upper:]' '[:lower:]' <<<"$kind")"
}


# ---- Q15 to Q18: Deployments, rollouts, namespaces, labels (Chapters 05 and 06) -----
jd() { kubectl -n "$1" get deployment "$2" -o "jsonpath=$3"; }
# rolled_out <namespace> <deployment>   latest rollout complete, no old Pods left
rolled_out() {
  local s gen obs want total upd avail
  s="$(jd "$1" "$2" '{.metadata.generation}|{.status.observedGeneration}|{.spec.replicas}|{.status.replicas}|{.status.updatedReplicas}|{.status.availableReplicas}')" || return 1
  IFS='|' read -r gen obs want total upd avail <<<"$s"
  [[ -n "$want" && "$gen" == "$obs" && "$want" == "$total" && "$want" == "$upd" && "$want" == "$avail" ]]
}
same_uid() { [[ -f "${STATE}/$3" && "$(jd "$1" "$2" '{.metadata.uid}')" == "$(cat "${STATE}/$3")" ]]; }

q15() {
  [[ "$(kubectl get namespace p1-staging -o jsonpath='{.metadata.labels.env}')" == "staging" ]] &&
  [[ "$(jd p1-staging relay '{range .spec.template.spec.containers[*]}{.name}={.image} {end}')" == "relay-container=nginx:1.27 " ]] &&
  [[ "$(jd p1-staging relay '{.spec.replicas}')" == "3" ]] &&
  rolled_out p1-staging relay
}
q16() {
  same_uid p1-ganymede atlas atlas-uid &&
  [[ "$(jd p1-ganymede atlas '{.spec.template.spec.containers[*].image}')" == "$(cat "${STATE}/atlas-good-image")" ]] &&
  rolled_out p1-ganymede atlas &&
  file_is "$C/16/broken-revision" "$(cat "${STATE}/atlas-broken-revision")"
}
q17() {
  same_uid p1-ganymede orbit orbit-uid &&
  [[ "$(jd p1-ganymede orbit '{.spec.template.spec.containers[*].image}')" == "nginx:1.27" ]] &&
  [[ "$(jd p1-ganymede orbit '{.spec.strategy.rollingUpdate.maxUnavailable}|{.spec.strategy.rollingUpdate.maxSurge}')" == "0|1" ]] &&
  [[ "$(jd p1-ganymede orbit '{.metadata.annotations.kubernetes\.io/change-cause}')" == "orbit to 1.27" ]] &&
  rolled_out p1-ganymede orbit
}
q18() {
  local uid rows
  uid="$(cat "${STATE}/drone-quarantine-uid" 2>/dev/null)" && [[ -n "$uid" ]] &&
  rows="$(kubectl -n p1-ganymede get pods -o jsonpath='{range .items[*]}{.metadata.uid}|{.metadata.labels.app}|{.metadata.ownerReferences[*].kind}|{.status.phase}{"\n"}{end}')" &&
  [[ "$(awk -F'|' -v u="$uid" '$1==u' <<<"$rows")" == "${uid}|drone-quarantine||Running" ]] &&
  [[ "$(jd p1-ganymede drone '{.spec.replicas}/{.status.readyReplicas}')" == "3/3" ]]
}

# ---- one check per question: a question is either done or not ---------------------
q1()  { q1_contexts && q1_namespace; }
q2()  { q2_container && q2_labels && q2_port && q2_ready; }
q3()  { q3_ready && q3_command && q3_kept; }
q4()  { q4_token && q4_container; }
q5()  { q5_pod && q5_requests && q5_limits; }
q6()  { q6_spec && q6_ran && q6_code; }
q7()  { q7_protected && q7_only && q7_audit; }
q8()  { q8_ga && q8_others && q8_temp; }
q9()  { q9_pods && q9_count; }
q10() { q10_file && q10_containers && q10_ready; }
q11() { q11_cm && q11_secret && q11_sa && q11_svc; }
q12() { q12_api && q12_type && q12_namespaced; }
q13() {
  q13_line 1 list pods p1-titan && q13_line 2 get secrets p1-titan &&
  q13_line 3 create pods p1-io && q13_line 4 list pods p1-io
}
q14() { q14_image && q14_proxy && q14_dns; }

check_weighted 1 3 "every context is listed in ${C}/1/contexts, and ${C}/1/namespace holds the default namespace of ${CTX_B}" \
  "kubectl config get-contexts -o name; each context's namespace is in kubectl config view" q1
check_weighted 2 6 "(p1-io) Pod courier: one container courier-container (nginx:1.27), labels app=courier and tier=edge, port 80, ready" \
  "kubectl run cannot name the container: --dry-run=client -o yaml, edit, apply" q2
check_weighted 3 7 "(p1-europa) Pod ledger runs sleep 3600 and is ready, with its image, labels, and annotation kept" \
  "the command is immutable: get -o yaml, fix it, kubectl replace --force -f" q3
check_weighted 4 6 "${C}/4/token holds the token and ${C}/4/container names the container that crashed" \
  "a restarted container's earlier output: kubectl logs --previous, with -c for one container" q4
check_weighted 5 5 "(p1-titan) Pod cruncher: one busybox:1.36 container, requests 50m/32Mi, limit 64Mi memory and no CPU limit, Running" \
  "start from kubectl run --dry-run=client -o yaml and set limits.memory only" q5
check_weighted 6 5 "(p1-io) Pod migrate ran once and exited 4, and ${C}/6/exit-code holds importer's exit code" \
  "--restart=Never, the command after --; .status.containerStatuses[0].state.terminated.exitCode" q6
check_weighted 7 5 "(p1-callisto) exactly the db/cache Pods have protected=true, and exactly the env=prod Pods have audit=q4-2026" \
  "set-based selector -l 'tier in (db,cache)'; kubectl annotate accepts -l" q7
check_weighted 8 4 "(p1-callisto) stage=beta became stage=ga, other stage labels kept, and no Pod has the label temp" \
  "--overwrite changes an existing value; a trailing - removes a label" q8
check_weighted 9 5 "${C}/9/pods lists the Pods with an nginx:1.26 container, and ${C}/9/containers holds the container count" \
  "look at every container (.spec.containers[*]), not just the first" q9
check_weighted 10 6 "${C}/10/gateway.yaml holds the manifest, and Pod gateway (p1-io) runs gateway (nginx:1.27, MODE=edge) and helper (busybox:1.36), both ready" \
  "generate with --dry-run=client -o yaml, add the second container, apply the file; the helper needs sleep 3600" q10
check_weighted 11 6 "(p1-europa) ConfigMap ledger-config, Secret ledger-db, ServiceAccount ledger-sa, and Service ledger-svc (8080 -> 80) exist as specified" \
  "kubectl create configmap / secret generic / serviceaccount, and kubectl expose pod ledger" q11
check_weighted 12 4 "${C}/12/ holds the CronJob group/version, the type of runAsNonRoot, and whether Namespaces are namespaced" \
  "kubectl api-resources, kubectl explain, kubectl api-resources --namespaced=false" q12
check_weighted 13 6 "${C}/13/answers holds the four yes/no answers about ServiceAccount auditor, in order" \
  "kubectl auth can-i VERB RESOURCE -n NS --as=${SA}; the file needs exactly four lines" q13
check_weighted 14 6 "${C}/14/ holds the kube-apiserver image and the kinds that manage kube-proxy and CoreDNS" \
  "kubectl -n kube-system get pod -l ... -o jsonpath; follow metadata.ownerReferences to the top" q14
check_weighted 15 7 "namespace p1-staging (env=staging) runs Deployment relay: 3 ready replicas, one container relay-container (nginx:1.27)" \
  "kubectl create deployment names the container after the image: --dry-run=client -o yaml, edit, apply" q15
check_weighted 16 7 "(p1-ganymede) atlas is rolled back to its last working revision, and ${C}/16/broken-revision names the broken one" \
  "kubectl rollout history deployment/atlas, then --revision=N to see each template; kubectl rollout undo --to-revision=N" q16
check_weighted 17 6 "(p1-ganymede) orbit runs nginx:1.27 with maxUnavailable 0, maxSurge 1, and change-cause 'orbit to 1.27'" \
  "the container is not called nginx; the strategy lives under spec.strategy.rollingUpdate" q17
check_weighted 18 6 "(p1-ganymede) the quarantined drone Pod has app=drone-quarantine and no owner, and drone is back to 3 ready Pods" \
  "find the Pod by its annotation; kubectl label --overwrite" q18

echo
report_elapsed "${STATE}/start" "$EXAM_MINUTES"
KBOOK_PASS_PERCENT=$EXAM_PASS_PERCENT finish_checks
