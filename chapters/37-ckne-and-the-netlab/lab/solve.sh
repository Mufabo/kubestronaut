#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require
nl_script <<'EOS'
# Task 1
echo 10.0.1.2 > /root/answers/37/beta-ip
# Task 2
ip netns list | grep -qx hello || ip netns add hello
# Task 3
ip netns exec gamma ip link set eth0 up
EOS
