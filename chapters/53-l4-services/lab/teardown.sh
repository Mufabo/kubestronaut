#!/usr/bin/env bash
# Remove the lab namespace, the IP pool, and the outside client. The cluster stays.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
require_lab_cluster
docker rm -f ch53-outside >/dev/null 2>&1 || true
kubectl delete ciliumloadbalancerippools.cilium.io ch53-pool --ignore-not-found >/dev/null
lab_teardown_ns "$LAB_NS"
lab_course_remove "$LAB_ANSWERS"
