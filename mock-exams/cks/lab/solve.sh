#!/usr/bin/env bash
# Reference solution for every question (used by the test loop on cp1).
# Human-readable version: solutions.md
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
C=$COURSE

# Q1: deny all ingress, then allow frontend to api on 8080.
kubectl -n cks-shop apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 8080
YAML

# Q2: compare each binary with the published checksum; delete the others.
want="$(curl -fsSL "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubeadm.sha512")"
for f in "${C}"/2/kubeadm-*; do
  [[ "$(sha512sum "$f" | cut -d' ' -f1)" == "$want" ]] || rm -f "$f"
done

# Q3: no cluster-admin; a namespaced Role with exactly the verbs needed.
kubectl delete clusterrolebinding deployer-admin >/dev/null
kubectl -n cks-ci create role deployer --verb=get,list,create,update --resource=deployments.apps >/dev/null
kubectl -n cks-ci create rolebinding deployer --role=deployer --serviceaccount=cks-ci:deployer >/dev/null

# Q5: load the profile on node2 (its name is inside the file), then use it.
# shellcheck disable=SC2029
on node2 "sudo apparmor_parser -q ${AA_FILE}"
kubectl -n cks-sys patch deployment writer -p "{\"spec\":{\"template\":{\"spec\":{\"securityContext\":{\"appArmorProfile\":{\"type\":\"Localhost\",\"localhostProfile\":\"${AA_PROFILE}\"}}}}}}" >/dev/null

# Q6: the profile into node1's kubelet directory, then the Pod.
scp -q -o BatchMode=yes "${C}/6/trace.json" node1:/tmp/trace.json
# shellcheck disable=SC2029
on node1 "sudo install -D -m 0644 /tmp/trace.json ${SECCOMP_DIR}/trace.json && rm /tmp/trace.json"
kubectl -n cks-sys apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: tracer
spec:
  nodeSelector:
    kubernetes.io/hostname: node1
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: cks/trace.json
  containers:
    - name: tracer
      image: busybox:1.36
      command: ["sleep", "infinity"]
YAML

# Q7: make payments comply, then enforce.
kubectl -n cks-pci patch deployment payments -p '{"spec":{"template":{"spec":{
  "securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},
  "containers":[{"name":"payments","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}}}' >/dev/null
kubectl label --overwrite namespace cks-pci pod-security.kubernetes.io/enforce=restricted >/dev/null

# Q9: the RuntimeClass, and the Deployment on it.
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: sandboxed
handler: runsc
YAML
kubectl -n cks-sbx patch deployment untrusted -p '{"spec":{"template":{"spec":{"runtimeClassName":"sandboxed"}}}}' >/dev/null

# Q10: deny untagged and :latest images in Deployments in cks-prod; digests pass.
kubectl apply -f - >/dev/null <<'YAML'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: cks-no-latest
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["deployments"]
  validations:
    - expression: >-
        object.spec.template.spec.containers.all(c,
          c.image.contains('@sha256:') ||
          (c.image.substring(c.image.lastIndexOf('/') + 1).contains(':') &&
           !c.image.endsWith(':latest')))
      message: "images must name a tag other than latest, or a digest"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: cks-no-latest
spec:
  policyName: cks-no-latest
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: cks-prod
YAML

# Q11: the digest the Pod runs, from its status.
image_id="$(kubectl -n cks-prod get pods -l app=cache -o jsonpath='{.items[0].status.containerStatuses[0].imageID}')"
kubectl -n cks-prod set image deployment/cache "nginx=nginx@${image_id##*@}" >/dev/null

# Q12: pinned base, no token, a user of its own.
cat > "${C}/12/Dockerfile" <<'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
RUN useradd --uid 10001 --no-create-home appuser
USER appuser
CMD ["python", "app.py"]
EOF

# Q14: Falco's alert names the Namespace and the Pod.
culprit_seen() {
  found="$(on node1 "sudo journalctl -u ${FALCO_UNIT} --no-pager -o cat" |
    sed -n 's/.*file=\/etc\/sudoers .*k8s_pod_name=\([^ ]*\) k8s_ns_name=\([^ ]*\).*/\2\/\1/p' | tail -1)"
  [[ -n "$found" ]]
}
wait_for "Falco's alert for /etc/sudoers" 120 culprit_seen
printf '%s\n' "$found" > "${C}/14/culprit.txt"
kubectl -n "${found%%/*}" delete pod "${found##*/}" --wait=false >/dev/null

# Q15: read-only root, with an emptyDir where httpd writes its PID file and logs.
kubectl -n cks-run patch deployment site -p '{"spec":{"template":{"spec":{
  "volumes":[{"name":"logs","emptyDir":{}}],
  "containers":[{"name":"httpd","securityContext":{"readOnlyRootFilesystem":true},
    "volumeMounts":[{"name":"logs","mountPath":"/usr/local/apache2/logs"}]}]}}}}' >/dev/null

# ---- the API server: questions 4, 8, and 13 in one edit ------------------------------
key="$(head -c 32 /dev/urandom | base64)"
sudo mkdir -p "$(dirname "$ENC_CONFIG")" "$(dirname "$AUDIT_POLICY")" "$(dirname "$AUDIT_LOG")"
sudo tee "$ENC_CONFIG" >/dev/null <<YAML
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - secretbox:
          keys:
            - name: cks-key
              secret: ${key}
      - identity: {}
YAML
sudo chmod 600 "$ENC_CONFIG"
sudo tee "$AUDIT_POLICY" >/dev/null <<'YAML'
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
  - RequestReceived
rules:
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets"]
  - level: RequestResponse
    namespaces: ["cks-prod"]
    verbs: ["create", "update", "patch", "delete"]
    resources:
      - group: "apps"
        resources: ["deployments"]
  - level: None
YAML
sudo sed -i \
  -e 's/--enable-admission-plugins=ServiceAccount$/--enable-admission-plugins=NodeRestriction/' \
  -e "s|^    - kube-apiserver\$|    - kube-apiserver\n    - --encryption-provider-config=${ENC_CONFIG}\n    - --audit-policy-file=${AUDIT_POLICY}\n    - --audit-log-path=${AUDIT_LOG}\n    - --audit-log-maxage=5\n    - --audit-log-maxbackup=3|" \
  -e "s|^    volumeMounts:\$|    volumeMounts:\n    - mountPath: $(dirname "$ENC_CONFIG")\n      name: enc\n      readOnly: true\n    - mountPath: ${AUDIT_POLICY}\n      name: audit-policy\n      readOnly: true\n    - mountPath: $(dirname "$AUDIT_LOG")\n      name: audit-log|" \
  -e "s|^  volumes:\$|  volumes:\n  - hostPath:\n      path: $(dirname "$ENC_CONFIG")\n      type: DirectoryOrCreate\n    name: enc\n  - hostPath:\n      path: ${AUDIT_POLICY}\n      type: File\n    name: audit-policy\n  - hostPath:\n      path: $(dirname "$AUDIT_LOG")\n      type: DirectoryOrCreate\n    name: audit-log|" \
  "$APISERVER_MANIFEST"
wait_for "the API server to come back with its new flags" 300 apiserver_restarted_with "--audit-policy-file=${AUDIT_POLICY}"
# Q8: rewrite the Secrets, so they are encrypted too.
secrets="$(kubectl -n cks-pci get secrets -o json)"
kubectl replace -f - <<<"$secrets" >/dev/null

# ---- wait for everything to settle --------------------------------------------------
for d in cks-sys/writer cks-pci/payments cks-sbx/untrusted cks-prod/cache cks-run/site; do
  kubectl -n "${d%%/*}" rollout status "deployment/${d##*/}" --timeout=300s >/dev/null
done
kubectl -n cks-sys wait --for=condition=Ready pod/tracer --timeout=180s >/dev/null
# rollout status returns while old Pods still terminate; wait until only the
# new ones are left, and the deleted culprit is gone.
settled() {
  local d app pods
  for d in cks-sys/writer:2 cks-pci/payments:2 cks-sbx/untrusted:1 cks-prod/cache:1 cks-run/site:2; do
    app="${d#*/}"; app="${app%%:*}"
    pods="$(kubectl -n "${d%%/*}" get pods -l "app=${app}" -o name 2>/dev/null)"
    [[ -n "$pods" && "$(wc -l <<<"$pods")" -eq "${d##*:}" ]] || return 1
  done
  ! kubectl -n "${found%%/*}" get pod "${found##*/}" >/dev/null 2>&1
}
wait_for "old Pods to terminate" 180 settled
