#!/usr/bin/env bash
# Automated reference solution (used by CI). Human-readable version: solutions.md
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster

# Task 1: the node with the control-plane role
cp_node="$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o name | cut -d/ -f2)"
printf '%s\n' "$cp_node" > "$F_CP"

# Task 2: the Pod labelled component=etcd
kubectl -n kube-system get pods -l component=etcd -o name | cut -d/ -f2 > "$F_ETCD"

# Task 3: static Pods run from manifest files on the control plane node, so
# their mirror Pods are named <component>-<node name>
kubectl -n kube-system get pods -o name | cut -d/ -f2 | grep -- "-${cp_node}\$" > "$F_STATIC"

# Task 4: where the scheduler placed the Pod
kubectl -n "$LAB_NS" get pod where-am-i -o jsonpath='{.spec.nodeName}' > "$F_NODE"

# Task 5: APIVERSION is the third column from the end of the table
kubectl api-resources --api-group=apps | awk '$NF=="Deployment"{print $(NF-2)}' > "$F_API"
