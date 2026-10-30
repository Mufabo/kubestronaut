#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

k() { kubectl -n "$LAB_NS" "$@"; }
# The password setup generated; the reader must not be able to guess it.
expected_pw() { [[ -f "${here}/.state/db-password" ]] && cat "${here}/.state/db-password"; }
# has_env <pod> <NAME=value>: the running container prints this exact line.
has_env() {
  local out
  out="$(k exec "$1" -- env 2>/dev/null)" || return 1
  grep -Fxq -- "$2" <<<"$out"
}
# running <pod>
running() { [[ "$(k get pod "$1" -o jsonpath='{.status.phase}' 2>/dev/null)" == Running ]]; }

t1() {
  local data
  # shellcheck disable=SC2016  # go-template syntax, not shell expansion
  data="$(k get configmap app-config -o go-template='{{range $k, $v := .data}}{{$k}}={{$v}}{{"\n"}}{{end}}')" || return 1
  [[ "$data" == $'FEATURE_FLAG=on\nLOG_LEVEL=info' ]]
}

t2() {
  local keys type user pass want
  type="$(k get secret db-credentials -o jsonpath='{.type}')" || return 1
  [[ "$type" == Opaque ]] || return 1
  # shellcheck disable=SC2016  # go-template syntax, not shell expansion
  keys="$(k get secret db-credentials -o go-template='{{range $k, $v := .data}}{{$k}}{{"\n"}}{{end}}')" || return 1
  [[ "$keys" == $'password\nusername' ]] || return 1
  user="$(k get secret db-credentials -o jsonpath='{.data.username}')" || return 1
  pass="$(k get secret db-credentials -o jsonpath='{.data.password}')" || return 1
  want="$(expected_pw)" || return 1
  [[ -n "$want" && "$(base64 -d <<<"$user")" == app && "$(base64 -d <<<"$pass")" == "$want" ]]
}

t3() {
  local refs ref_name key want
  running web || return 1
  [[ "$(k get pod web -o jsonpath='{.spec.containers[0].image}')" == nginx:1.27 ]] || return 1
  [[ "$(k get pod web -o jsonpath='{.spec.containers[*].name}' | wc -w | tr -d '[:space:]')" == 1 ]] || return 1
  # Every key of app-config comes in through envFrom, not through one env entry.
  refs="$(k get pod web -o jsonpath='{.spec.containers[0].envFrom[*].configMapRef.name}')" || return 1
  [[ " ${refs} " == *" app-config "* ]] || return 1
  # DB_PASSWORD is a reference to the Secret, not a literal value.
  ref_name="$(k get pod web -o jsonpath='{.spec.containers[0].env[?(@.name=="DB_PASSWORD")].valueFrom.secretKeyRef.name}')"
  key="$(k get pod web -o jsonpath='{.spec.containers[0].env[?(@.name=="DB_PASSWORD")].valueFrom.secretKeyRef.key}')"
  [[ "$ref_name" == db-credentials && "$key" == password ]] || return 1
  want="$(expected_pw)" || return 1
  has_env web LOG_LEVEL=info && has_env web FEATURE_FLAG=on && has_env web "DB_PASSWORD=${want}"
}

t4() {
  local node fp limit divisor
  running reporter || return 1
  [[ "$(k get pod reporter -o jsonpath='{.spec.containers[0].image}')" == busybox:1.36 ]] || return 1
  [[ "$(k get pod reporter -o jsonpath='{.spec.containers[0].resources.limits.memory}')" == 64Mi ]] || return 1
  fp="$(k get pod reporter -o jsonpath='{.spec.containers[0].env[?(@.name=="POD_NAME")].valueFrom.fieldRef.fieldPath}')"
  [[ "$fp" == metadata.name ]] || return 1
  fp="$(k get pod reporter -o jsonpath='{.spec.containers[0].env[?(@.name=="NODE_NAME")].valueFrom.fieldRef.fieldPath}')"
  [[ "$fp" == spec.nodeName ]] || return 1
  limit="$(k get pod reporter -o jsonpath='{.spec.containers[0].env[?(@.name=="MEM_LIMIT")].valueFrom.resourceFieldRef.resource}')"
  divisor="$(k get pod reporter -o jsonpath='{.spec.containers[0].env[?(@.name=="MEM_LIMIT")].valueFrom.resourceFieldRef.divisor}')"
  [[ "$limit" == limits.memory && "$divisor" == 1Mi ]] || return 1
  node="$(k get pod reporter -o jsonpath='{.spec.nodeName}')" || return 1
  has_env reporter POD_NAME=reporter && has_env reporter "NODE_NAME=${node}" && has_env reporter MEM_LIMIT=64
}

t5() {
  local vols mounts want
  running config-viewer || return 1
  [[ "$(k get pod config-viewer -o jsonpath='{.spec.containers[0].image}')" == busybox:1.36 ]] || return 1
  vols="$(k get pod config-viewer -o go-template='{{range .spec.volumes}}{{.name}}:{{with .configMap}}configmap/{{.name}}{{end}}{{with .secret}}secret/{{.secretName}}{{end}}{{"\n"}}{{end}}')" || return 1
  grep -Fq -- ":configmap/app-config" <<<"$vols" || return 1
  grep -Fq -- ":secret/db-credentials" <<<"$vols" || return 1
  # The Secret must be mounted at /etc/db, read-only.
  mounts="$(k get pod config-viewer -o go-template='{{range .spec.containers}}{{range .volumeMounts}}{{.mountPath}} {{.readOnly}}{{"\n"}}{{end}}{{end}}')" || return 1
  grep -Fxq -- "/etc/db true" <<<"$mounts" || return 1
  grep -Fq -- "/etc/app " <<<"$mounts" || return 1
  [[ "$(k exec config-viewer -- cat /etc/app/LOG_LEVEL 2>/dev/null)" == info ]] || return 1
  [[ "$(k exec config-viewer -- cat /etc/app/FEATURE_FLAG 2>/dev/null)" == on ]] || return 1
  [[ "$(k exec config-viewer -- cat /etc/db/username 2>/dev/null)" == app ]] || return 1
  want="$(expected_pw)" || return 1
  [[ -n "$want" && "$(k exec config-viewer -- cat /etc/db/password 2>/dev/null)" == "$want" ]]
}

check 1 "ConfigMap app-config has exactly LOG_LEVEL=info and FEATURE_FLAG=on" \
  "kubectl -n ${LAB_NS} get configmap app-config -o yaml shows the keys and values" t1
check 2 "Secret db-credentials is Opaque, with username=app and password copied from legacy-db" \
  "decode legacy-db's password with: kubectl -n ${LAB_NS} get secret legacy-db -o jsonpath='{.data.password}' | base64 -d" t2
check 3 "Pod web runs nginx:1.27 with app-config through envFrom and DB_PASSWORD from the Secret" \
  "check 'kubectl -n ${LAB_NS} exec web -- env' and the Pod spec for envFrom and secretKeyRef" t3
check 4 "Pod reporter gets its name, node and memory limit (64) from the downward API" \
  "use fieldRef for metadata.name and spec.nodeName, resourceFieldRef with divisor 1Mi for the limit" t4
check 5 "Pod config-viewer mounts app-config at /etc/app and db-credentials read-only at /etc/db" \
  "the Secret mount needs readOnly: true; the ConfigMap files are named after the keys" t5

finish_checks
