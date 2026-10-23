#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"

require_lab_cluster

# The Gateway API CRDs are cluster-wide. Installing the pinned version is
# idempotent; teardown leaves them in place, because other labs may use them.
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml" >/dev/null

lab_teardown_ns "$LAB_NS"
remove_controller
# Cluster-scoped leftovers from a previous run.
kubectl delete gatewayclass "$LAB_GATEWAYCLASS" --ignore-not-found >/dev/null
lab_create_ns "$LAB_NS"

k() { kubectl -n "$LAB_NS" "$@"; }
# The backends the routes point at. They have no Pods: the lab checks the
# objects the API server accepts, not traffic.
k create service clusterip shop --tcp=80:80 >/dev/null
k create service clusterip docs --tcp=80:80 >/dev/null
k create service clusterip api --tcp=8080:80 >/dev/null

# The GatewayClass the Gateway in Task 4 refers to. No controller runs in this
# cluster, so nothing reconciles it; the lab checks what the API server stores.
kubectl apply -f - >/dev/null <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: ${LAB_GATEWAYCLASS}
spec:
  controllerName: example.com/edge-controller
YAML

# Task 6: a backend that answers, and a client to send requests from.
k apply -f "${here}/../manifests/web.yaml" >/dev/null
k rollout status deployment/web --timeout=180s >/dev/null
wait_for "pod client Running" 180 pod_phase_is "$LAB_NS" client Running

info "Lab ready. Namespace: ${LAB_NS} (use -n ${LAB_NS}, or run: make use-namespace CH=12)"
