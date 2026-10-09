#!/usr/bin/env bash
# Automated reference solution (used by CI). Human-readable version: solutions.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_lab_cluster
C=$COURSE

# Q1
kubectl config get-contexts -o name > "$C/1/contexts"
ctx_field "$CTX_B" namespace > "$C/1/namespace"

# Q2: generate, rename the container, apply
kubectl -n p1-io run courier --image=nginx:1.27 --labels=app=courier,tier=edge --port=80 --dry-run=client -o yaml |
  sed 's/^    name: courier$/    name: courier-container/' | kubectl -n p1-io apply -f - >/dev/null

# Q3: the command is immutable, so export, fix, and replace
kubectl -n p1-europa get pod ledger -o yaml > "${STATE}/ledger.yaml"
sed -i 's/sleeep/sleep/' "${STATE}/ledger.yaml"
kubectl replace --force -f "${STATE}/ledger.yaml" >/dev/null
rm -f "${STATE}/ledger.yaml"

# Q4
kubectl -n p1-titan logs beacon -c agent --previous | grep -m1 '^token=' | cut -d= -f2 > "$C/4/token"
echo agent > "$C/4/container"

# Q5
kubectl -n p1-titan apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: cruncher
spec:
  containers:
    - name: cruncher
      image: busybox:1.36
      command: ["sleep", "3600"]
      resources:
        requests: {cpu: 50m, memory: 32Mi}
        limits: {memory: 64Mi}
YAML

# Q6
kubectl -n p1-io run migrate --image=busybox:1.36 --restart=Never -- sh -c 'echo migration finished; exit 4' >/dev/null
kubectl -n p1-io get pod importer -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' > "$C/6/exit-code"

# Q7
kubectl -n p1-callisto label pods -l 'tier in (db,cache)' protected=true >/dev/null
kubectl -n p1-callisto annotate pods -l env=prod audit=q4-2026 >/dev/null

# Q8
kubectl -n p1-callisto label pods -l stage=beta stage=ga --overwrite >/dev/null
kubectl -n p1-callisto label pods -l temp temp- >/dev/null

# Q9
kubectl -n p1-callisto get pods -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[*].image}{"\n"}{end}' |
  awk '/nginx:1\.26/{print $1}' > "$C/9/pods"
kubectl -n p1-callisto get pods -o jsonpath='{.items[*].spec.containers[*].name}' | wc -w | tr -d '[:space:]' > "$C/9/containers"

# Q10: generate, append the helper container, create from the file
kubectl run gateway --image=nginx:1.27 --labels=app=gateway --env=MODE=edge --dry-run=client -o yaml > "$C/10/gateway.yaml"
awk '{print} $0 == "  containers:" {print "  - name: helper"; print "    image: busybox:1.36"; print "    command: [sleep, \"3600\"]"}' \
  "$C/10/gateway.yaml" > "${STATE}/gateway.yaml"
mv "${STATE}/gateway.yaml" "$C/10/gateway.yaml"
kubectl -n p1-io apply -f "$C/10/gateway.yaml" >/dev/null

# Q11
kubectl -n p1-europa create configmap ledger-config --from-literal=currency=EUR --from-literal=rounding=half-even >/dev/null
kubectl -n p1-europa create secret generic ledger-db --from-literal=user=ledger --from-literal=password=l3dg3r-pw >/dev/null
kubectl -n p1-europa create serviceaccount ledger-sa >/dev/null
kubectl -n p1-europa expose pod ledger --name=ledger-svc --port=8080 --target-port=80 >/dev/null

# Q12
echo batch/v1 > "$C/12/cronjob-api"
kubectl explain pod.spec.containers.securityContext.runAsNonRoot | sed -n 's/^FIELD:.*<\([A-Za-z]*\)>.*/\1/p' > "$C/12/run-as-non-root"
echo no > "$C/12/namespaced"

# Q13
SA=system:serviceaccount:p1-titan:auditor
{ kubectl auth can-i list pods -n p1-titan --as="$SA" || true
  kubectl auth can-i get secrets -n p1-titan --as="$SA" || true
  kubectl auth can-i create pods -n p1-io --as="$SA" || true
  kubectl auth can-i list pods -n p1-io --as="$SA" || true
} > "$C/13/answers"

# Q14
kubectl -n kube-system get pods -l component=kube-apiserver -o jsonpath='{.items[0].spec.containers[0].image}' > "$C/14/apiserver-image"
echo DaemonSet > "$C/14/proxy-owner"
echo Deployment > "$C/14/dns-owner"

info "Waiting for the new Pods"
started() { [[ "$(kubectl -n p1-io get pod "$1" -o jsonpath='{.status.phase}')" =~ ^(Running|Failed)$ ]]; }
for p in courier migrate gateway; do
  wait_for "pod ${p} started" 180 started "$p"
done
wait_for "pod cruncher Running" 180 pod_phase_is p1-titan cruncher Running
wait_for "pod ledger Running" 180 pod_phase_is p1-europa ledger Running
gateway_ready() { [[ "$(kubectl -n p1-io get pod gateway -o jsonpath='{.status.containerStatuses[*].ready}')" == "true true" ]]; }
wait_for "both gateway containers ready" 180 gateway_ready
