#!/usr/bin/env bash
# Score the CKAD simulator. Read-only. One check per question (all or nothing),
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
# in_pod <namespace> <pod> <container> <command...>   the command's output
in_pod() { local ns=$1 pod=$2 c=$3; shift 3; kubectl -n "$ns" exec "$pod" -c "$c" -- "$@" 2>/dev/null; }
# ready_endpoints <namespace> <service>   how many ready endpoints the Service has
ready_endpoints() {
  kubectl -n "$1" get endpointslices -l "kubernetes.io/service-name=$2" \
    -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{"\n"}{end}' 2>/dev/null | grep -c .
}
# reach <pod in ckad-net> <host>   an HTTP GET from the Pod succeeds within 2 seconds
reach() { kubectl -n ckad-net exec "$1" -- wget -qO- -T 2 "http://$2" >/dev/null 2>&1; }
# can <verb> <resource>   kubectl auth can-i for the deployer ServiceAccount
can() { kubectl auth can-i "$1" "$2" -n ckad-sec --as=system:serviceaccount:ckad-sec:deployer 2>/dev/null; }

# ---- Q1 Build and save an image ---------------------------------------------------
q1() {
  local tar="${C}/1/ckad-web.tar" manifest cfg config
  [[ -f "$tar" ]] || return 1
  manifest="$(tar -xOf "$tar" manifest.json 2>/dev/null)" || return 1
  grep -Eq '"RepoTags":\[[^]]*ckad-web:2\.0"' <<<"$manifest" || return 1
  cfg="$(grep -o '"Config":"[^"]*"' <<<"$manifest" | cut -d'"' -f4)"
  [[ -n "$cfg" ]] || return 1
  config="$(tar -xOf "$tar" "${cfg%%$'\n'*}" 2>/dev/null)" || return 1
  grep -Fq '"APP_VERSION=2.0"' <<<"$config"
}

# ---- Q2 Native sidecar ---------------------------------------------------------------
q2() {
  local out
  [[ "$(jp ckad-design pod/logger '{.spec.initContainers[?(@.name=="shipper")].restartPolicy}')" == Always ]] || return 1
  [[ "$(jp ckad-design pod/logger '{.spec.initContainers[?(@.name=="shipper")].image}')" == busybox:1.36 ]] || return 1
  running ckad-design logger || return 1
  out="$(kubectl -n ckad-design logs logger -c shipper --tail=5 2>/dev/null)"
  grep -q '^order [0-9]' <<<"$out"
}

# ---- Q3 DaemonSet on every node ------------------------------------------------------
q3() {
  local nodes
  nodes="$(kubectl get nodes -o name 2>/dev/null | grep -c .)"
  [[ "$(jp ckad-design daemonset/node-agent '{.spec.template.spec.containers[0].image}')" == busybox:1.36 ]] || return 1
  [[ "$nodes" -gt 0 ]] || return 1
  [[ "$(jp ckad-design daemonset/node-agent '{.status.desiredNumberScheduled}/{.status.numberReady}')" == "${nodes}/${nodes}" ]]
}

# ---- Q4 Memory-backed scratch space --------------------------------------------------
q4() {
  [[ "$(jp ckad-design pod/scratch '{.spec.volumes[?(@.name=="scratch")].emptyDir.medium}/{.spec.volumes[?(@.name=="scratch")].emptyDir.sizeLimit}')" == Memory/64Mi ]] || return 1
  [[ "$(jp ckad-design pod/scratch '{.spec.containers[0].volumeMounts[?(@.name=="scratch")].mountPath}')" == /scratch ]] || return 1
  running ckad-design scratch
}

# ---- Q5 Rolling update ---------------------------------------------------------------
q5() {
  [[ "$(jp ckad-deploy deployment/frontend '{.spec.strategy.type}/{.spec.strategy.rollingUpdate.maxSurge}/{.spec.strategy.rollingUpdate.maxUnavailable}')" == RollingUpdate/1/0 ]] || return 1
  [[ "$(jp ckad-deploy deployment/frontend '{.spec.template.spec.containers[0].image}')" == nginx:1.27 ]] || return 1
  [[ "$(jp ckad-deploy deployment/frontend '{.spec.replicas}/{.status.replicas}/{.status.updatedReplicas}/{.status.availableReplicas}')" == 4/4/4/4 ]]
}

# ---- Q6 Canary -------------------------------------------------------------------------
q6() {
  [[ "$(jp ckad-deploy deployment/checkout-canary '{.spec.replicas}/{.spec.template.spec.containers[0].image}')" == 1/nginx:1.27 ]] || return 1
  [[ "$(jp ckad-deploy deployment/checkout-canary '{.spec.template.metadata.labels.app}/{.spec.template.metadata.labels.track}')" == checkout/canary ]] || return 1
  [[ "$(jp ckad-deploy deployment/checkout '{.spec.replicas}/{.status.readyReplicas}')" == 4/4 ]] || return 1
  [[ "$(jp ckad-deploy service/checkout '{.spec.selector}')" == '{"app":"checkout"}' ]] || return 1
  [[ "$(ready_endpoints ckad-deploy checkout)" == 5 ]]
}

# ---- Q7 Helm upgrade that keeps a value -----------------------------------------------
q7() {
  local out values
  out="$(helm -n ckad-deploy status cache 2>/dev/null)" || return 1
  grep -Fq "STATUS: deployed" <<<"$out" || return 1
  values="$(helm -n ckad-deploy get values cache --all -o json 2>/dev/null)" || return 1
  grep -Fq '"replicaCount":3' <<<"$values" && grep -Fq '"tag":"1.27"' <<<"$values" && grep -Fq '"greeting":"hello-ckad"' <<<"$values" || return 1
  [[ "$(jp ckad-deploy deployment/cache '{.spec.replicas}/{.spec.template.spec.containers[0].image}/{.status.readyReplicas}')" == 3/nginx:1.27/3 ]] || return 1
  [[ "$(jp ckad-deploy configmap/cache-config '{.data.greeting}')" == hello-ckad ]]
}

# ---- Q8 Kustomize overlay -------------------------------------------------------------
q8() {
  local built
  built="$(kubectl kustomize "${C}/8/overlays/prod" 2>/dev/null)" || return 1
  grep -q '^  namespace: ckad-deploy$' <<<"$built" && grep -q '^  replicas: 2$' <<<"$built" || return 1
  [[ "$(jp ckad-deploy deployment/ledger '{.metadata.labels.env}/{.spec.template.metadata.labels.env}')" == prod/prod ]] || return 1
  [[ "$(jp ckad-deploy deployment/ledger '{.spec.replicas}/{.status.readyReplicas}')" == 2/2 ]]
}

# ---- Q9 A removed API version ---------------------------------------------------------
q9() {
  grep -Eq '^apiVersion: batch/v1$' "${C}/9/cleanup.yaml" 2>/dev/null || return 1
  [[ "$(jp ckad-ops cronjob/cleanup '{.spec.schedule}|{.spec.jobTemplate.spec.template.spec.containers[0].image}')" == "*/30 * * * *|busybox:1.36" ]]
}

# ---- Q10 Probes -----------------------------------------------------------------------
q10() {
  local rp='{.spec.template.spec.containers[0].readinessProbe' lp='{.spec.template.spec.containers[0].livenessProbe'
  [[ "$(jp ckad-ops deployment/api "${rp}.httpGet.path}:${rp}.httpGet.port}/${rp}.periodSeconds}")" == /:80/5 ]] || return 1
  [[ "$(jp ckad-ops deployment/api "${lp}.tcpSocket.port}/${lp}.initialDelaySeconds}/${lp}.periodSeconds}")" == 80/10/20 ]] || return 1
  [[ "$(jp ckad-ops deployment/api '{.spec.replicas}/{.status.replicas}/{.status.updatedReplicas}/{.status.readyReplicas}')" == 2/2/2/2 ]]
}

# ---- Q11 Errors from one container ----------------------------------------------------
q11() {
  [[ -f "${C}/11/errors.txt" ]] && [[ "$(cat "${C}/11/errors.txt")" == $'ERROR disk full on /data\nERROR retry limit reached' ]]
}

# ---- Q12 Debug a crashing Deployment --------------------------------------------------
q12() {
  [[ "$(jp ckad-ops deployment/reports '{.spec.template.spec.containers[0].command[2]}')" == "test -f /config/settings.conf || { echo 'missing /config/settings.conf'; exit 1; }; sleep 3600" ]] || return 1
  [[ "$(jp ckad-ops deployment/reports '{.spec.replicas}/{.status.replicas}/{.status.updatedReplicas}/{.status.readyReplicas}')" == 1/1/1/1 ]]
}

# ---- Q13 ConfigMap from a file and a Secret, as volumes --------------------------------
q13() {
  [[ "$(jp ckad-sec configmap/db-config '{.data.db\.properties}')" == $'host=db.ckad-sec.svc\nport=5432' ]] || return 1
  [[ "$(jp ckad-sec secret/db-cred '{.data.username}' | base64 -d 2>/dev/null)" == app ]] || return 1
  [[ "$(jp ckad-sec secret/db-cred '{.data.password}' | base64 -d 2>/dev/null)" == s3cr3t ]] || return 1
  running ckad-sec db-client || return 1
  [[ "$(in_pod ckad-sec db-client db-client cat /etc/db-config/db.properties)" == $'host=db.ckad-sec.svc\nport=5432' ]] || return 1
  [[ "$(in_pod ckad-sec db-client db-client cat /etc/db-cred/password)" == s3cr3t ]]
}

# ---- Q14 Security context -------------------------------------------------------------
q14() {
  local sc='{.spec.containers[0].securityContext'
  running ckad-sec hardened || return 1
  [[ "$(in_pod ckad-sec hardened hardened id -u):$(in_pod ckad-sec hardened hardened id -g)" == 1000:3000 ]] || return 1
  [[ "$(jp ckad-sec pod/hardened '{.spec.securityContext.runAsNonRoot}{.spec.containers[0].securityContext.runAsNonRoot}')" == *true* ]] || return 1
  [[ "$(jp ckad-sec pod/hardened "${sc}.allowPrivilegeEscalation}/${sc}.readOnlyRootFilesystem}/${sc}.capabilities.drop[*]}")" == false/true/ALL ]]
}

# ---- Q15 ServiceAccount and RBAC ------------------------------------------------------
q15() {
  [[ "$(jp ckad-sec rolebinding/deployer-binding '{.roleRef.kind}/{.roleRef.name}')" == Role/deploy-editor ]] || return 1
  [[ "$(can create deployments.apps)/$(can patch deployments.apps)/$(can list deployments.apps)" == yes/yes/yes ]] || return 1
  [[ "$(can delete deployments.apps)/$(can get secrets)" == no/no ]] || return 1
  [[ "$(jp ckad-sec deployment/ci '{.spec.template.spec.serviceAccountName}/{.status.readyReplicas}')" == deployer/1 ]]
}

# ---- Q16 Requests and limits under a quota ---------------------------------------------
q16() {
  local r='{.spec.template.spec.containers[0].resources'
  [[ "$(jp ckad-quota deployment/burst "${r}.requests.cpu}/${r}.requests.memory}/${r}.limits.cpu}/${r}.limits.memory}")" == 100m/64Mi/200m/128Mi ]] || return 1
  [[ "$(jp ckad-quota deployment/burst '{.spec.replicas}/{.status.readyReplicas}')" == 3/3 ]] || return 1
  [[ "$(jp ckad-quota resourcequota/compute '{.spec.hard.pods}/{.spec.hard.requests\.cpu}/{.spec.hard.requests\.memory}/{.spec.hard.limits\.cpu}/{.spec.hard.limits\.memory}')" == 5/1/1Gi/2/2Gi ]]
}

# ---- Q17 A custom resource -------------------------------------------------------------
q17() {
  [[ "$(jp ckad-sec caches.ckad.kbook.io/session-cache '{.spec.size}/{.spec.replicas}')" == medium/3 ]]
}

# ---- Q18 A Service that reaches nothing -------------------------------------------------
q18() {
  local out
  [[ "$(jp ckad-net deployment/catalog '{.spec.template.spec.containers[0].ports[0].name}/{.spec.template.spec.containers[0].ports[0].containerPort}')" == http/80 ]] || return 1
  out="$(kubectl -n ckad-net exec probe -- wget -qO- -T 3 http://catalog 2>/dev/null)"
  grep -q 'Welcome to nginx' <<<"$out"
}

# ---- Q19 NetworkPolicy ------------------------------------------------------------------
q19() {
  [[ "$(jp ckad-net networkpolicy/db-access '{.spec.podSelector.matchLabels.app}')" == db ]] || return 1
  [[ "$(jp ckad-net networkpolicy/db-access '{.spec.ingress[*].ports[*].port}')" == 80 ]] || return 1
  reach api db || return 1
  reach web db && return 1
  reach probe db && return 1
  reach web shop
}

# ---- Q20 Service and Ingress -------------------------------------------------------------
q20() {
  local paths
  [[ "$(jp ckad-net service/cart '{.spec.type}/{.spec.ports[0].port}/{.spec.ports[0].targetPort}')" == ClusterIP/8080/80 ]] || return 1
  [[ "$(ready_endpoints ckad-net cart)" == 2 ]] || return 1
  [[ "$(jp ckad-net ingress/store '{.spec.ingressClassName}/{.spec.rules[0].host}')" == nginx/store.ckad.example.test ]] || return 1
  paths="$(jp ckad-net ingress/store '{range .spec.rules[0].http.paths[*]}{.path}|{.pathType}|{.backend.service.name}:{.backend.service.port.number}{"\n"}{end}' | sort)"
  [[ "$paths" == $'/cart|Prefix|cart:8080\n/shop|Prefix|shop:80' ]]
}

check_weighted 1 6 "${C}/1/ckad-web.tar is image ckad-web:2.0, with APP_VERSION=2.0" \
  "edit ENV in the Dockerfile; docker build -t ckad-web:2.0 .; docker save -o ckad-web.tar ckad-web:2.0" q1
check_weighted 2 6 "(ckad-design) Pod logger has a native sidecar shipper (busybox:1.36) that prints the app's log, and runs" \
  "a sidecar is an init container with restartPolicy: Always" q2
check_weighted 3 4 "(ckad-design) DaemonSet node-agent (busybox:1.36) has a ready Pod on every node, the control plane included" \
  "the control plane node is tainted; add a toleration" q3
check_weighted 4 4 "(ckad-design) Pod scratch mounts volume scratch (emptyDir, medium Memory, sizeLimit 64Mi) at /scratch, and runs" \
  "emptyDir: {medium: Memory, sizeLimit: 64Mi}" q4
check_weighted 5 5 "(ckad-deploy) Deployment frontend: RollingUpdate maxSurge 1 / maxUnavailable 0, nginx:1.27, all 4 replicas updated and available" \
  "kubectl patch the strategy, then kubectl set image" q5
check_weighted 6 6 "(ckad-deploy) Deployment checkout-canary (1 replica, nginx:1.27, app=checkout track=canary); Service checkout reaches all 5 Pods" \
  "a separate Deployment whose Pods also match the Service's selector" q6
check_weighted 7 5 "(ckad-deploy) Helm release cache: deployed, 3 replicas of nginx:1.27, greeting still hello-ckad" \
  "helm upgrade --reuse-values, or set greeting again" q7
check_weighted 8 5 "(ckad-deploy) overlay ${C}/8/overlays/prod applied: Deployment ledger, 2 replicas, label env=prod on it and its Pods" \
  "resources: [../../base], namespace, replicas, labels; kubectl apply -k" q8
check_weighted 9 3 "(ckad-ops) ${C}/9/cleanup.yaml uses batch/v1, and CronJob cleanup exists" \
  "kubectl api-resources shows the served version of CronJob" q9
check_weighted 10 4 "(ckad-ops) Deployment api: readiness GET / on 80 every 5s, liveness TCP 80 after 10s every 20s, rolled out" \
  "kubectl explain deployment.spec.template.spec.containers.livenessProbe" q10
check_weighted 11 3 "${C}/11/errors.txt holds the ERROR lines of container worker of Pod batch-runner, in order" \
  "kubectl -n ckad-ops logs batch-runner -c worker | grep ERROR" q11
check_weighted 12 5 "(ckad-ops) Deployment reports runs and is ready, with its command unchanged" \
  "kubectl logs shows the missing file; fix the ConfigMap key or the volume's items" q12
check_weighted 13 6 "(ckad-sec) ConfigMap db-config from db.properties, Secret db-cred, and Pod db-client reading both from volumes" \
  "kubectl create configmap --from-file; kubectl create secret generic --from-literal" q13
check_weighted 14 6 "(ckad-sec) Pod hardened runs as 1000:3000, non-root, no privilege escalation, read-only root, all capabilities dropped" \
  "runAsUser/runAsGroup/runAsNonRoot in the Pod; the rest in the container's securityContext" q14
check_weighted 15 6 "(ckad-sec) ServiceAccount deployer may get/list/create/update/patch Deployments only, and Deployment ci runs as it" \
  "kubectl create role/rolebinding; kubectl auth can-i --as=system:serviceaccount:ckad-sec:deployer" q15
check_weighted 16 4 "(ckad-quota) Deployment burst: requests 100m/64Mi, limits 200m/128Mi, 3 ready Pods; quota compute unchanged" \
  "kubectl set resources deployment burst --requests=... --limits=..." q16
check_weighted 17 3 "(ckad-sec) Cache session-cache: size medium, 3 replicas" \
  "kubectl api-resources | grep -i cache; kubectl explain cache.spec" q17
check_weighted 18 6 "(ckad-net) Service catalog serves nginx to Pod probe; Deployment catalog unchanged" \
  "the Service's targetPort must name a port the Pods have" q18
check_weighted 19 7 "(ckad-net) NetworkPolicy db-access: only app=api Pods reach db, on port 80; other traffic unchanged" \
  "podSelector app=db, policyTypes Ingress, from podSelector app=api, port 80" q19
check_weighted 20 6 "(ckad-net) Service cart (8080 to 80) and Ingress store: /shop to shop:80, /cart to cart:8080, Prefix" \
  "kubectl expose deployment cart --port=8080 --target-port=80; kubectl create ingress --rule ... --rule ..." q20

echo
report_elapsed "${STATE}/start" "$EXAM_MINUTES"
KBOOK_PASS_PERCENT=$EXAM_PASS_PERCENT finish_checks
