#!/usr/bin/env bash
# Score the Part II simulator. Read-only. One check per question (all or
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
# in_pod <namespace> <pod> <container> <command...>   the command's output, unquoted
in_pod() { local ns=$1 pod=$2 c=$3; shift 3; kubectl -n "$ns" exec "$pod" -c "$c" -- "$@" 2>/dev/null; }
# word <file>   the file's content, without whitespace
word() { tr -d '[:space:]' < "$1"; }

# ---- Q1 ConfigMap and env --------------------------------------------------------
q1() {
  local keys
  # shellcheck disable=SC2016  # go-template syntax, not shell expansion
  keys="$(kubectl -n p2-web get configmap site-config -o go-template='{{range $k, $v := .data}}{{$k}}={{$v}}{{"\n"}}{{end}}' 2>/dev/null)" || return 1
  [[ "$keys" == $'LANG=en\nTHEME=dark' ]] || return 1
  [[ "$(jp p2-web pod/site '{.spec.containers[0].envFrom[*].configMapRef.name}')" == site-config ]] || return 1
  running p2-web site || return 1
  [[ "$(in_pod p2-web site site printenv THEME)" == dark ]]
}

# ---- Q2 Secret into an env var ---------------------------------------------------
q2() {
  [[ "$(jp p2-web secret/api-key '{.type}')" == Opaque ]] || return 1
  [[ "$(jp p2-web secret/api-key '{.data.token}' | base64 -d)" == s3-p2-token ]] || return 1
  [[ "$(jp p2-web pod/worker '{.spec.containers[0].env[?(@.name=="API_TOKEN")].valueFrom.secretKeyRef.name}')" == api-key ]] || return 1
  running p2-web worker || return 1
  [[ "$(in_pod p2-web worker worker printenv API_TOKEN)" == s3-p2-token ]]
}

# ---- Q3 Guaranteed Pod with readiness ---------------------------------------------
q3() {
  [[ "$(jp p2-web pod/guarded '{.spec.containers[0].image}')" == nginx:1.27 ]] || return 1
  [[ "$(jp p2-web pod/guarded '{.spec.containers[0].resources.requests.cpu}/{.spec.containers[0].resources.limits.cpu}')" == 100m/100m ]] || return 1
  [[ "$(jp p2-web pod/guarded '{.spec.containers[0].resources.requests.memory}/{.spec.containers[0].resources.limits.memory}')" == 64Mi/64Mi ]] || return 1
  [[ "$(jp p2-web pod/guarded '{.spec.containers[0].readinessProbe.httpGet.port}')" == 80 ]] || return 1
  [[ "$(jp p2-web pod/guarded '{.status.qosClass}')" == Guaranteed ]] || return 1
  running p2-web guarded
}

# ---- Q4 Job with completions -----------------------------------------------------
q4() {
  [[ "$(jp p2-batch job/migrate '{.spec.completions}/{.spec.parallelism}/{.spec.backoffLimit}')" == 3/1/1 ]] || return 1
  [[ "$(jp p2-batch job/migrate '{.spec.template.spec.containers[0].image}')" == busybox:1.36 ]] || return 1
  [[ "$(jp p2-batch job/migrate '{.status.conditions[?(@.type=="Complete")].status}')" == True ]]
}

# ---- Q5 CronJob and a run started from it ------------------------------------------
q5() {
  [[ "$(jp p2-batch cronjob/report '{.spec.schedule}|{.spec.concurrencyPolicy}')" == "0 3 * * *|Forbid" ]] || return 1
  [[ "$(jp p2-batch job/report-now '{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}')" == CronJob/report ]] || return 1
  [[ "$(jp p2-batch job/report-now '{.status.conditions[?(@.type=="Complete")].status}')" == True ]] || return 1
  [[ "$(kubectl -n p2-batch logs job/report-now 2>/dev/null)" == report ]]
}

# ---- Q6 Init container writes a value -----------------------------------------------
q6() {
  [[ "$(jp p2-data pod/pipeline '{.status.initContainerStatuses[?(@.name=="seed")].state.terminated.reason}')" == Completed ]] || return 1
  running p2-data pipeline || return 1
  [[ "$(in_pod p2-data pipeline consume cat /work/value)" == 42 ]]
}

# ---- Q7 PVC that keeps data -------------------------------------------------------
q7() {
  [[ "$(jp p2-data pvc/archive '{.spec.resources.requests.storage}/{.status.phase}')" == 200Mi/Bound ]] || return 1
  running p2-data keeper || return 1
  [[ "$(in_pod p2-data keeper keeper cat /archive/ok)" == ok ]]
}

# ---- Q8 Service selector ----------------------------------------------------------
q8() {
  local got want
  got="$(kubectl -n p2-edge get endpointslices -l kubernetes.io/service-name=shop -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{"\n"}{end}' 2>/dev/null | sort)"
  want="$(kubectl -n p2-edge get pods -l app=shop -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' 2>/dev/null | sort)"
  [[ -n "$want" && "$got" == "$want" ]]
}

# ---- Q9 Ingress --------------------------------------------------------------------
q9() {
  [[ "$(jp p2-edge ingress/shop '{.spec.ingressClassName}')" == nginx ]] &&
  [[ "$(jp p2-edge ingress/shop '{.spec.rules[0].host}')" == shop.p2.example.test ]] &&
  [[ "$(jp p2-edge ingress/shop '{.spec.rules[0].http.paths[0].path}/{.spec.rules[0].http.paths[0].pathType}')" == "/app/Prefix" ]] &&
  [[ "$(jp p2-edge ingress/shop '{.spec.rules[0].http.paths[0].backend.service.name}:{.spec.rules[0].http.paths[0].backend.service.port.number}')" == shop:80 ]]
}

# ---- Q10 Helm release ---------------------------------------------------------------
q10() {
  local out
  out="$(helm -n p2-release status web 2>/dev/null)" || return 1
  grep -Fq "STATUS: deployed" <<<"$out" || return 1
  [[ "$(jp p2-release deployment/web '{.spec.replicas}')" == 2 ]]
}

# ---- Q11 Rollback ------------------------------------------------------------------
q11() {
  [[ "$(jp p2-release deployment/api '{.spec.template.spec.containers[0].image}')" == nginx:1.26 ]]
}

# ---- Q12 Answer file ---------------------------------------------------------------
q12() {
  [[ -f "${C}/12/message.txt" ]] && [[ "$(cat "${C}/12/message.txt")" == "fatal: license expired" ]]
}

# ---- Q13 PodDisruptionBudget at the served version -----------------------------------
q13() {
  [[ "$(jp p2-ops pdb/api-guard '{.apiVersion}/{.spec.minAvailable}/{.spec.selector.matchLabels.app}')" == "policy/v1/1/api" ]]
}

# ---- Q14 Relabel ---------------------------------------------------------------------
q14() {
  [[ "$(jp p2-ops pod/tool-1 '{.metadata.labels.stage}')" == new ]] &&
  [[ "$(jp p2-ops pod/tool-2 '{.metadata.labels.stage}')" == new ]] &&
  [[ "$(jp p2-ops pod/tool-3 '{.metadata.labels.stage}')" == new ]] &&
  [[ "$(jp p2-ops pod/keep '{.metadata.labels.stage}')" == keep ]]
}

check_weighted 1 7 "(p2-web) ConfigMap site-config has THEME=dark and LANG=en, and Pod site loads it with envFrom and runs" \
  "kubectl -n p2-web create configmap site-config --from-literal=...; the Pod uses envFrom" q1
check_weighted 2 7 "(p2-web) Secret api-key (Opaque) holds token=s3-p2-token; Pod worker sets API_TOKEN from it and runs" \
  "kubectl create secret generic; env with valueFrom.secretKeyRef" q2
check_weighted 3 8 "(p2-web) Pod guarded (nginx:1.27): requests equal limits (100m, 64Mi), readiness httpGet on 80, QoS Guaranteed, Ready" \
  "Guaranteed needs equal requests and limits for CPU and memory" q3
check_weighted 4 7 "(p2-batch) Job migrate: busybox:1.36, 3 completions, parallelism 1, backoffLimit 1, Complete" \
  "kubectl create job cannot set completions; write YAML" q4
check_weighted 5 7 "(p2-batch) CronJob report (0 3 * * *, Forbid, busybox echo report), and Job report-now created from it, Complete, logs 'report'" \
  "kubectl create job --from=cronjob/report" q5
check_weighted 6 7 "(p2-data) Pod pipeline: init container seed writes 42 to /work/value; consume reads 42 from /work/value and runs" \
  "an init container finishes before the main container starts" q6
check_weighted 7 7 "(p2-data) PVC archive (200Mi, Bound); Pod keeper mounts it at /archive and /archive/ok holds ok" \
  "the default class binds once a Pod uses the claim" q7
check_weighted 8 8 "(p2-edge) Service shop routes to every ready shop Pod" \
  "the Service's selector must match the Pods' labels" q8
check_weighted 9 7 "(p2-edge) Ingress shop: class nginx, host shop.p2.example.test, path /app (Prefix) to Service shop port 80" \
  "a trailing * in kubectl create ingress --rule gives Prefix" q9
check_weighted 10 7 "(p2-release) Helm release web installed from ${C}/10/chart is deployed, with replicaCount 2" \
  "helm -n p2-release install web ${C}/10/chart --set replicaCount=2" q10
check_weighted 11 7 "(p2-release) Deployment api runs nginx:1.26 again (rolled back)" \
  "kubectl -n p2-release rollout undo deployment/api --to-revision=N, after reading the history" q11
check_weighted 12 7 "${C}/12/message.txt holds the fatal line the crash Pod prints" \
  "kubectl -n p2-ops logs crash; the line is the message, without other text" q12
check_weighted 13 7 "(p2-ops) PodDisruptionBudget api-guard: policy/v1, minAvailable 1, selector app=api" \
  "kubectl api-resources --api-group=policy shows the served version" q13
check_weighted 14 7 "(p2-ops) Pods tool-1, tool-2, tool-3 have stage=new; keep still has stage=keep" \
  "kubectl label pod NAME stage=new --overwrite; leave keep alone" q14

echo
report_elapsed "${STATE}/start" "$EXAM_MINUTES"
KBOOK_PASS_PERCENT=$EXAM_PASS_PERCENT finish_checks
