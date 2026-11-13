#!/usr/bin/env bash
# Automated reference solution (used by the test loop on cp1). Human-readable
# version: solutions.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
# shellcheck source=/dev/null
source "${here}/common.sh"
require_snapshot "$LAB_SNAPSHOT"
require_lab_cluster

# Task 1: the policy, then the API server's flags, volumes, and mounts.
sudo mkdir -p "$(dirname "$AUDIT_POLICY")" "$(dirname "$AUDIT_LOG")"
sudo tee "$AUDIT_POLICY" >/dev/null <<YAML
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
  - RequestReceived
rules:
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets", "configmaps"]
  - level: RequestResponse
    namespaces: ["${LAB_NS}"]
    resources:
      - group: ""
        resources: ["pods"]
  - level: None
YAML
sudo sed -i \
  -e "s|^    - kube-apiserver\$|    - kube-apiserver\n    - --audit-policy-file=${AUDIT_POLICY}\n    - --audit-log-path=${AUDIT_LOG}\n    - --audit-log-maxage=7\n    - --audit-log-maxbackup=2\n    - --audit-log-maxsize=50|" \
  -e "s|^    volumeMounts:\$|    volumeMounts:\n    - mountPath: ${AUDIT_POLICY}\n      name: audit-policy\n      readOnly: true\n    - mountPath: $(dirname "$AUDIT_LOG")\n      name: audit-log|" \
  -e "s|^  volumes:\$|  volumes:\n  - hostPath:\n      path: ${AUDIT_POLICY}\n      type: File\n    name: audit-policy\n  - hostPath:\n      path: $(dirname "$AUDIT_LOG")\n      type: DirectoryOrCreate\n    name: audit-log|" \
  "$APISERVER_MANIFEST"
auditing_apiserver_up() {
  apiserver_flags | grep -qx -- "--audit-policy-file=${AUDIT_POLICY}" && kubectl get --raw /readyz >/dev/null 2>&1
}
wait_for "the API server to come back with audit logging" 300 auditing_apiserver_up

# Task 2: Falco's alert names the Pod; its owner is the Deployment.
falco_pod() {
  pod="$(on node1 "sudo journalctl -u ${FALCO_UNIT} --no-pager -o cat" |
    sed -n 's/.*file=\/etc\/shadow .*k8s_pod_name=\([^ ]*\) k8s_ns_name='"${LAB_NS}"'.*/\1/p' | tail -1)"
  [[ -n "$pod" ]]
}
wait_for "Falco's alert for /etc/shadow" 120 falco_pod
rs="$(kubectl -n "$LAB_NS" get pod "$pod" -o jsonpath='{.metadata.ownerReferences[0].name}')"
deploy="$(kubectl -n "$LAB_NS" get replicaset "$rs" -o jsonpath='{.metadata.ownerReferences[0].name}')"
printf '%s\n' "$deploy" > "$FALCO_FILE"
kubectl -n "$LAB_NS" scale deployment "$deploy" --replicas=0 >/dev/null

# Task 3: the rule, in its own file; Falco reloads changed rules by itself, a
# restart makes sure.
# shellcheck disable=SC2029
on node1 "sudo tee ${FALCO_RULES} >/dev/null" <<'YAML'
- rule: Write below etc in container
  desc: A process in a container opened a file below /etc for writing
  condition: open_write and container and fd.name startswith /etc/
  output: File below /etc opened for writing (file=%fd.name command=%proc.cmdline)
  priority: WARNING
YAML
since="$(on node1 'date +%s')"
on node1 "sudo systemctl restart ${FALCO_UNIT}"
wait_for "Falco running on node1" 60 falco_running

# Task 4: read-only root, with emptyDir volumes where nginx writes.
kubectl -n "$LAB_NS" patch deployment web --type=strategic -p '{"spec":{"template":{"spec":{
  "volumes":[{"name":"cache","emptyDir":{}},{"name":"run","emptyDir":{}}],
  "containers":[{"name":"nginx",
    "securityContext":{"readOnlyRootFilesystem":true},
    "volumeMounts":[{"name":"cache","mountPath":"/var/cache/nginx"},{"name":"run","mountPath":"/var/run"}]}]}}}}' >/dev/null

# Task 5: label the Pod, and a policy that selects it and allows nothing.
kubectl -n "$LAB_NS" label pod miner status=quarantined >/dev/null
kubectl -n "$LAB_NS" apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: quarantine
spec:
  podSelector:
    matchLabels:
      status: quarantined
  policyTypes:
    - Ingress
    - Egress
YAML

kubectl -n "$LAB_NS" rollout status deployment/web --timeout=180s >/dev/null
# rollout status returns while old Pods are still terminating; wait until they,
# and the scaled-down suspect's Pod, are gone.
pods_settled() {
  [[ "$(kubectl -n "$LAB_NS" get pods -l app=web -o name | wc -l)" -eq 2 &&
     -z "$(kubectl -n "$LAB_NS" get pods -l "app=${deploy}" -o name)" ]]
}
wait_for "old Pods to terminate" 120 pods_settled
# Falco takes a few seconds after its restart to watch system calls again: try
# the new rule until it reports.
rule_reports() {
  local out
  kubectl -n "$LAB_NS" exec canary -- sh -c ': >> /etc/group' >/dev/null 2>&1
  out="$(on node1 "sudo journalctl -u ${FALCO_UNIT} --no-pager -o cat --since @${since}")"
  [[ "$out" == *"file=/etc/group"*"k8s_pod_name=canary"* ]]
}
wait_for "Falco to report the new rule" 90 rule_reports
