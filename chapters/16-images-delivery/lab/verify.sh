#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

k() { kubectl -n "$LAB_NS" "$@"; }
# jp <resource> <jsonpath>
jp() { k get "$1" -o "jsonpath=$2" 2>/dev/null; }

t1() {
  # the image is on the worker node (kind load puts it on every node)
  local out rows
  out="$(docker exec "${CLUSTER_NAME}-worker" crictl images 2>/dev/null)" || return 1
  rows="$(grep -F -- "ch16-app" <<<"$out" || true)"
  grep -Fq -- "1.0" <<<"$rows"
}

t2() {
  [[ "$(jp deployment/app '{.spec.template.spec.containers[0].image}')" == "$LAB_IMAGE" ]] &&
  [[ "$(jp deployment/app '{.spec.template.spec.containers[0].imagePullPolicy}')" == IfNotPresent ]] &&
  [[ "$(jp deployment/app '{.status.readyReplicas}')" == 2 ]] &&
  [[ "$(k exec deploy/app -- wget -qO- http://localhost/ 2>/dev/null)" == "hello from ch16" ]]
}

t3() {
  [[ "$(jp deployment/legacy '{.spec.strategy.type}')" == Recreate ]] &&
  [[ "$(jp deployment/legacy '{.status.readyReplicas}')" == 1 ]]
}

t4() {
  [[ "$(jp deployment/app '{.spec.strategy.type}')" == RollingUpdate ]] &&
  [[ "$(jp deployment/app '{.spec.strategy.rollingUpdate.maxUnavailable}')" == 0 ]] &&
  [[ "$(jp deployment/app '{.spec.strategy.rollingUpdate.maxSurge}')" == 1 ]]
}

t5() {
  [[ "$(jp secret/regcred '{.type}')" == kubernetes.io/dockerconfigjson ]] &&
  [[ "$(jp pod/private-app '{.spec.containers[0].image}')" == registry.example.test/team/app:1.0 ]] &&
  [[ "$(jp pod/private-app '{.spec.imagePullSecrets[0].name}')" == regcred ]]
}

check 1 "Image $LAB_IMAGE is built from lab/.state/app and loaded on the kind worker node" \
  "docker build -t $LAB_IMAGE lab/.state/app, then kind load docker-image $LAB_IMAGE --name $CLUSTER_NAME" t1
check 2 "Deployment app runs $LAB_IMAGE with IfNotPresent, 2 ready replicas, and serves the page" \
  "IfNotPresent stops the kubelet from looking for the image in a registry" t2
check 3 "Deployment legacy uses the Recreate strategy and is ready" \
  "Recreate stops every old Pod before it starts the new ones" t3
check 4 "Deployment app uses RollingUpdate with maxUnavailable 0 and maxSurge 1" \
  "the strategy fields are under spec.strategy.rollingUpdate" t4
check 5 "Secret regcred is dockerconfigjson, and Pod private-app pulls registry.example.test/team/app:1.0 with it" \
  "create the Secret with kubectl create secret docker-registry; the Pod cannot start without the registry" t5

finish_checks
