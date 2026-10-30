#!/usr/bin/env bash
# Score the CKAD simulator, set 2. Read-only. One check per question (all or
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
# in_pod <namespace> <pod> <container> <command...>   the command's output
in_pod() { local ns=$1 pod=$2 c=$3; shift 3; kubectl -n "$ns" exec "$pod" -c "$c" -- "$@" 2>/dev/null; }
# ready_endpoints <namespace> <service>   how many ready endpoints the Service has
ready_endpoints() {
  kubectl -n "$1" get endpointslices -l "kubernetes.io/service-name=$2" \
    -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{"\n"}{end}' 2>/dev/null | grep -c .
}
# can <verb> <resource> [subresource]   kubectl auth can-i for the viewer ServiceAccount
can() {
  kubectl auth can-i "$1" "$2" ${3:+--subresource="$3"} -n ckad2-sec --as=system:serviceaccount:ckad2-sec:viewer 2>/dev/null
}

# ---- Q1 An image that runs as a user and declares its port ------------------------
q1() {
  local tar="${C}/1/ckad2-api.tar" manifest cfg config
  [[ -f "$tar" ]] || return 1
  manifest="$(tar -xOf "$tar" manifest.json 2>/dev/null)" || return 1
  grep -Eq '"RepoTags":\[[^]]*ckad2-api:1\.1"' <<<"$manifest" || return 1
  cfg="$(grep -o '"Config":"[^"]*"' <<<"$manifest" | cut -d'"' -f4)"
  [[ -n "$cfg" ]] || return 1
  config="$(tar -xOf "$tar" "${cfg%%$'\n'*}" 2>/dev/null)" || return 1
  grep -Fq '"User":"1000"' <<<"$config" && grep -Fq '"8080/tcp"' <<<"$config"
}

# ---- Q2 An init container fills the web root -----------------------------------------
q2() {
  [[ "$(jp ckad2-design pod/web-cache '{.status.initContainerStatuses[?(@.name=="fetch")].state.terminated.reason}')" == Completed ]] || return 1
  [[ "$(jp ckad2-design pod/web-cache '{.spec.containers[?(@.name=="web")].image}')" == nginx:1.27 ]] || return 1
  running ckad2-design web-cache || return 1
  [[ "$(in_pod ckad2-design web-cache web cat /usr/share/nginx/html/index.html)" == "ckad2 ready" ]]
}

# ---- Q3 A CronJob with limits on its history and its runs ------------------------------
q3() {
  local j='{.spec.jobTemplate.spec'
  [[ "$(jp ckad2-design cronjob/cleanup '{.spec.schedule}|{.spec.successfulJobsHistoryLimit}|{.spec.failedJobsHistoryLimit}|{.spec.startingDeadlineSeconds}')" == "*/15 * * * *|2|1|60" ]] || return 1
  [[ "$(jp ckad2-design cronjob/cleanup "${j}.activeDeadlineSeconds}|${j}.template.spec.restartPolicy}|${j}.template.spec.containers[0].image}")" == "30|Never|busybox:1.36" ]]
}

# ---- Q4 A StatefulSet with a claim per replica -----------------------------------------
q4() {
  [[ "$(jp ckad2-design service/kv '{.spec.clusterIP}')" == None ]] || return 1
  [[ "$(jp ckad2-design statefulset/kv '{.spec.serviceName}|{.spec.replicas}|{.status.readyReplicas}|{.spec.template.spec.containers[0].image}')" == "kv|2|2|nginx:1.27" ]] || return 1
  [[ "$(jp ckad2-design statefulset/kv '{.spec.volumeClaimTemplates[0].metadata.name}|{.spec.volumeClaimTemplates[0].spec.resources.requests.storage}')" == "data|64Mi" ]] || return 1
  [[ "$(jp ckad2-design pvc/data-kv-0 '{.status.phase}')|$(jp ckad2-design pvc/data-kv-1 '{.status.phase}')" == "Bound|Bound" ]]
}

# ---- Q5 Recreate ------------------------------------------------------------------------
q5() {
  [[ "$(jp ckad2-deploy deployment/reports '{.spec.strategy.type}|{.spec.template.spec.containers[0].image}')" == "Recreate|nginx:1.27" ]] || return 1
  [[ "$(jp ckad2-deploy deployment/reports '{.spec.replicas}/{.status.replicas}/{.status.updatedReplicas}/{.status.availableReplicas}')" == 2/2/2/2 ]]
}

# ---- Q6 Blue/green switch ---------------------------------------------------------------
q6() {
  [[ "$(jp ckad2-deploy service/shop '{.spec.selector.app}|{.spec.selector.version}')" == "shop|green" ]] || return 1
  [[ "$(ready_endpoints ckad2-deploy shop)" == 3 ]] || return 1
  [[ "$(jp ckad2-deploy deployment/shop-green '{.spec.replicas}/{.status.readyReplicas}')" == 3/3 ]] || return 1
  [[ "$(jp ckad2-deploy deployment/shop-blue '{.spec.replicas}')" == 0 ]]
}

# ---- Q7 Helm rollback -------------------------------------------------------------------
q7() {
  local out values
  out="$(helm -n ckad2-deploy status catalog 2>/dev/null)" || return 1
  grep -Fq "STATUS: deployed" <<<"$out" || return 1
  grep -Eq "REVISION: ([3-9]|[1-9][0-9])" <<<"$out" || return 1
  values="$(helm -n ckad2-deploy get values catalog -o json 2>/dev/null)" || return 1
  grep -Fq '"tag":"1.26"' <<<"$values" || return 1
  [[ "$(jp ckad2-deploy deployment/catalog '{.spec.template.spec.containers[0].image}|{.spec.replicas}|{.status.replicas}|{.status.readyReplicas}')" == "nginx:1.26|1|1|1" ]]
}

# ---- Q8 Kustomize overlay with an image and a merged generator ----------------------------
q8() {
  local cm
  [[ -f "${C}/8/overlays/staging/kustomization.yaml" ]] || return 1
  [[ "$(jp ckad2-deploy deployment/staging-web '{.spec.template.spec.containers[0].image}|{.status.readyReplicas}')" == "nginx:1.27|1" ]] || return 1
  cm="$(jp ckad2-deploy deployment/staging-web '{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}')"
  [[ "$cm" == staging-app-config-* ]] || return 1
  [[ "$(jp ckad2-deploy "configmap/${cm}" '{.data.MODE}')" == staging ]]
}

# ---- Q9 A removed API version -------------------------------------------------------------
q9() {
  grep -Eq '^apiVersion: autoscaling/v2$' "${C}/9/hpa.yaml" 2>/dev/null || return 1
  [[ "$(jp ckad2-ops hpa/api '{.spec.scaleTargetRef.name}|{.spec.minReplicas}|{.spec.maxReplicas}')" == "api|1|3" ]]
}

# ---- Q10 A startup probe for a slow container ------------------------------------------------
q10() {
  local sp='{.spec.template.spec.containers[0].startupProbe' restarts
  [[ "$(jp ckad2-ops deployment/slow "${sp}.exec.command[*]}|${sp}.periodSeconds}|${sp}.failureThreshold}")" == "cat /tmp/ready|5|12" ]] || return 1
  [[ "$(jp ckad2-ops deployment/slow '{.spec.replicas}/{.status.replicas}/{.status.updatedReplicas}/{.status.readyReplicas}')" == 1/1/1/1 ]] || return 1
  restarts="$(kubectl -n ckad2-ops get pods -l app=slow -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' 2>/dev/null)"
  [[ "$restarts" == 0 ]]
}

# ---- Q11 Who uses the CPU? ---------------------------------------------------------------------
q11() {
  [[ -f "${C}/11/pod.txt" && "$(cat "${C}/11/pod.txt")" == burner ]]
}

# ---- Q12 A missing ConfigMap key -----------------------------------------------------------------
q12() {
  [[ "$(jp ckad2-ops configmap/client-config '{.data.API_URL}')" == "http://api" ]] || return 1
  running ckad2-ops api-client
}

# ---- Q13 A projected token with an audience -------------------------------------------------------
q13() {
  local vol t
  [[ "$(jp ckad2-sec serviceaccount/reporter '{.automountServiceAccountToken}')" == false ]] || return 1
  [[ "$(jp ckad2-sec pod/reporter '{.spec.serviceAccountName}')" == reporter ]] || return 1
  vol="$(jp ckad2-sec pod/reporter '{.spec.volumes[?(@.projected.sources[0].serviceAccountToken.audience=="reports")].name}')"
  [[ -n "$vol" ]] || return 1
  t="{.spec.volumes[?(@.name==\"${vol}\")].projected.sources[0].serviceAccountToken"
  [[ "$(jp ckad2-sec pod/reporter "${t}.expirationSeconds}|${t}.path}")" == "3600|token" ]] || return 1
  [[ "$(jp ckad2-sec pod/reporter "{.spec.containers[0].volumeMounts[?(@.name==\"${vol}\")].mountPath}")" == /var/run/reports ]] || return 1
  running ckad2-sec reporter || return 1
  kubectl -n ckad2-sec exec reporter -- test -s /var/run/reports/token 2>/dev/null
}

# ---- Q14 Read-only access to Pods and their logs ----------------------------------------------------
q14() {
  [[ "$(jp ckad2-sec rolebinding/viewer-binding '{.roleRef.kind}/{.roleRef.name}')" == Role/pod-viewer ]] || return 1
  [[ "$(can get pods)/$(can list pods)/$(can get pods log)" == yes/yes/yes ]] || return 1
  [[ "$(can delete pods)/$(can get secrets)/$(can create pods)" == no/no/no ]]
}

# ---- Q15 A TLS Secret from files ---------------------------------------------------------------------
q15() {
  [[ "$(jp ckad2-sec secret/web-tls '{.type}')" == kubernetes.io/tls ]] || return 1
  [[ "$(jp ckad2-sec secret/web-tls '{.data.tls\.crt}' | base64 -d 2>/dev/null)" == "$(cat "${C}/15/tls.crt")" ]] || return 1
  [[ "$(jp ckad2-sec pod/web-tls '{.spec.volumes[?(@.secret.secretName=="web-tls")].name}')" != "" ]] || return 1
  running ckad2-sec web-tls || return 1
  kubectl -n ckad2-sec exec web-tls -- test -f /etc/tls/tls.crt 2>/dev/null
}

# ---- Q16 LimitRange defaults ---------------------------------------------------------------------------
q16() {
  local l='{.spec.limits[?(@.type=="Container")]' r='{.spec.containers[0].resources'
  [[ "$(jp ckad2-quota limitrange/defaults "${l}.default.cpu}|${l}.default.memory}|${l}.defaultRequest.cpu}|${l}.defaultRequest.memory}")" == "200m|128Mi|100m|64Mi" ]] || return 1
  [[ "$(jp ckad2-quota pod/plain "${r}.limits.cpu}|${r}.limits.memory}|${r}.requests.cpu}|${r}.requests.memory}")" == "200m|128Mi|100m|64Mi" ]] || return 1
  running ckad2-quota plain
}

# ---- Q17 One capability, read-only root ------------------------------------------------------------------
q17() {
  local sc='{.spec.containers[0].securityContext'
  [[ "$(jp ckad2-sec pod/netadmin "${sc}.capabilities.drop[*]}|${sc}.capabilities.add[*]}|${sc}.readOnlyRootFilesystem}")" == "ALL|NET_ADMIN|true" ]] || return 1
  [[ "$(jp ckad2-sec pod/netadmin '{.spec.volumes[?(@.emptyDir)].name}')" != "" ]] || return 1
  [[ "$(jp ckad2-sec pod/netadmin '{.spec.containers[0].volumeMounts[*].mountPath}')" == *"/tmp"* ]] || return 1
  running ckad2-sec netadmin
}

# ---- Q18 Egress to one Service ---------------------------------------------------------------------------
q18() {
  [[ "$(jp ckad2-net networkpolicy/frontend-egress '{.spec.podSelector.matchLabels.app}|{.spec.policyTypes[*]}')" == "frontend|Egress" ]] || return 1
  kubectl -n ckad2-net exec frontend -- wget -qO- -T 3 http://backend:8080 >/dev/null 2>&1 || return 1
  ! kubectl -n ckad2-net exec frontend -- wget -qO- -T 3 http://other >/dev/null 2>&1
}

# ---- Q19 A NodePort ------------------------------------------------------------------------------------------
q19() {
  local ip out
  [[ "$(jp ckad2-net service/legacy-np '{.spec.type}|{.spec.ports[0].port}|{.spec.ports[0].nodePort}|{.spec.selector.app}')" == "NodePort|80|${NODE_PORT}|legacy" ]] || return 1
  ip="$(kubectl get node "${CLUSTER_NAME}-worker" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)"
  out="$(curl -s -m 5 "http://${ip}:${NODE_PORT}" 2>/dev/null)"
  grep -q 'Welcome to nginx' <<<"$out"
}

# ---- Q20 An Ingress with TLS and a default backend ----------------------------------------------------------
q20() {
  local i=ingress/portal
  [[ "$(jp ckad2-net "$i" '{.spec.ingressClassName}|{.spec.defaultBackend.service.name}:{.spec.defaultBackend.service.port.number}')" == "nginx|fallback:80" ]] || return 1
  [[ "$(jp ckad2-net "$i" '{.spec.rules[0].host}|{.spec.rules[0].http.paths[0].path}|{.spec.rules[0].http.paths[0].pathType}|{.spec.rules[0].http.paths[0].backend.service.name}:{.spec.rules[0].http.paths[0].backend.service.port.number}')" == "portal.ckad2.example.test|/api|Exact|api:80" ]] || return 1
  [[ "$(jp ckad2-net "$i" '{.spec.tls[0].hosts[*]}|{.spec.tls[0].secretName}')" == "portal.ckad2.example.test|portal-tls" ]]
}

check_weighted 1 5 "${C}/1/ckad2-api.tar is image ckad2-api:1.1, which runs as user 1000 and exposes 8080/tcp" \
  "USER and EXPOSE in the Dockerfile; docker build -t ckad2-api:1.1 .; docker save -o FILE ckad2-api:1.1" q1
check_weighted 2 5 "(ckad2-design) Pod web-cache: init container fetch wrote index.html, container web (nginx:1.27) serves 'ckad2 ready'" \
  "an emptyDir mounted in both, at /usr/share/nginx/html in web" q2
check_weighted 3 5 "(ckad2-design) CronJob cleanup: */15 * * * *, history 2 and 1, starting deadline 60s, active deadline 30s, restartPolicy Never" \
  "kubectl create cronjob, then edit; kubectl explain cronjob.spec" q3
check_weighted 4 5 "(ckad2-design) StatefulSet kv (2 ready, nginx:1.27) with headless Service kv and a 64Mi claim data per replica, Bound" \
  "volumeClaimTemplates; clusterIP: None; serviceName" q4
check_weighted 5 5 "(ckad2-deploy) Deployment reports: Recreate strategy, nginx:1.27, 2 replicas available" \
  "spec.strategy.type: Recreate (remove rollingUpdate), then set the image" q5
check_weighted 6 5 "(ckad2-deploy) Service shop sends to green (3 ready endpoints); shop-blue scaled to 0" \
  "patch the Service's selector to version: green, then scale shop-blue" q6
check_weighted 7 5 "(ckad2-deploy) Helm release catalog rolled back: deployed, image tag 1.26, 1 ready replica" \
  "helm history catalog; helm rollback catalog 1" q7
check_weighted 8 5 "(ckad2-deploy) overlay staging applied: Deployment staging-web, nginx:1.27, reading a staging-app-config-* ConfigMap with MODE=staging" \
  "namePrefix, namespace, images, and configMapGenerator with behavior: merge" q8
check_weighted 9 4 "(ckad2-ops) ${C}/9/hpa.yaml uses autoscaling/v2, and HPA api exists (1 to 3)" \
  "kubectl api-resources | grep -i horizontal" q9
check_weighted 10 4 "(ckad2-ops) Deployment slow: startup probe cat /tmp/ready every 5s, 12 failures allowed; ready, no restarts" \
  "startupProbe holds off the liveness probe until it succeeds once" q10
check_weighted 11 3 "${C}/11/pod.txt names the app=load Pod that uses the most CPU" \
  "kubectl -n ckad2-ops top pod -l app=load --sort-by=cpu" q11
check_weighted 12 4 "(ckad2-ops) ConfigMap client-config has API_URL=http://api, and Pod api-client runs" \
  "kubectl describe pod api-client shows CreateContainerConfigError and the missing key" q12
check_weighted 13 5 "(ckad2-sec) ServiceAccount reporter (no automount); Pod reporter runs as it with a projected token (audience reports, 3600s) at /var/run/reports/token" \
  "a projected volume with a serviceAccountToken source" q13
check_weighted 14 5 "(ckad2-sec) ServiceAccount viewer may get and list Pods and read their logs, nothing else (Role pod-viewer, RoleBinding viewer-binding)" \
  "the resource pods/log; kubectl auth can-i get pods --subresource=log --as=..." q14
check_weighted 15 5 "(ckad2-sec) TLS Secret web-tls from ${C}/15, mounted by Pod web-tls at /etc/tls" \
  "kubectl create secret tls web-tls --cert=... --key=..." q15
check_weighted 16 5 "(ckad2-quota) LimitRange defaults (limits 200m/128Mi, requests 100m/64Mi), and Pod plain got them" \
  "spec.limits with type: Container, default and defaultRequest" q16
check_weighted 17 5 "(ckad2-sec) Pod netadmin: all capabilities dropped but NET_ADMIN, read-only root file system, an emptyDir at /tmp, Running" \
  "capabilities: {drop: [ALL], add: [NET_ADMIN]}" q17
check_weighted 18 7 "(ckad2-net) NetworkPolicy frontend-egress: frontend reaches backend on 8080 by name, and nothing else" \
  "egress needs DNS too, and the port in a policy is the Pod's port, not the Service's" q18
check_weighted 19 6 "(ckad2-net) Service legacy-np: NodePort ${NODE_PORT} to legacy's Pods on port 80, answering on a node's address" \
  "kubectl expose deployment legacy --name=legacy-np --type=NodePort --port=80, then set nodePort" q19
check_weighted 20 7 "(ckad2-net) Ingress portal: TLS with portal-tls, Exact /api to api:80 for portal.ckad2.example.test, default backend fallback:80" \
  "spec.tls, spec.defaultBackend, and a rule; kubectl create ingress --default-backend and --rule with tls=" q20

echo
report_elapsed "${STATE}/start" "$EXAM_MINUTES"
KBOOK_PASS_PERCENT=$EXAM_PASS_PERCENT finish_checks
