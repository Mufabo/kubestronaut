#!/usr/bin/env bash
# shellcheck disable=SC2029  # variables in ssh commands are meant to expand on cp1
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

# Task 1: the files 4.1.1 and 4.1.9 audit.
ssh node2 "sudo chmod 600 /lib/systemd/system/kubelet.service ${KUBELET_CONFIG}"

# Task 2: one flag in each manifest; the kubelet restarts the static Pods.
for c in "${COMPONENTS[@]}"; do
  sudo sed -i "s|^    - ${c}\$|    - ${c}\n    - --profiling=false|" "${MANIFESTS}/${c}.yaml"
done
for c in "${COMPONENTS[@]}"; do
  wait_for "${c} with --profiling=false" 300 profiling_off "$c"
done

# Task 3
ssh node1 "sudo sed -i -e '/^  anonymous:/{n;s/enabled: true/enabled: false/}' -e '/^authorization:/{n;s/mode: AlwaysAllow/mode: Webhook/}' -e '/^readOnlyPort:/d' ${KUBELET_CONFIG} && sudo systemctl restart kubelet"
readonly_port_closed() { ! curl -s -m 2 -o /dev/null http://node1:10255/healthz; }
wait_for "node1's read-only port to close" 120 readonly_port_closed
wait_for "node1 Ready" 180 node_ready node1

# Task 4: keep the file whose checksum matches the published one.
want="$(curl -fsSL "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl.sha512")"
for f in "${BIN_DIR}"/kubectl-*; do
  if [[ "$(sha512sum "$f" | cut -d' ' -f1)" != "$want" ]]; then sudo rm -f "$f"; fi
done

# Task 5
kubectl -n "$LAB_NS" apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-metadata
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 169.254.169.254/32
YAML
client_reaches_web() { kubectl -n "$LAB_NS" exec client -- wget -qO- -T 3 http://web >/dev/null 2>&1; }
wait_for "client to reach web" 120 client_reaches_web
