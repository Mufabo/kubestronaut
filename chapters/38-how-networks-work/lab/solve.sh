#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${here}/../../../tools/lib.sh"
# shellcheck source=/dev/null
source "${here}/lab.env"
netlab_require
secret="$(cat "${here}/.state/secret")"
nl_script <<EOS
# Task 1: the server's end of the cable is down
ip netns exec server ip link set eth0 up
# Task 2: ss -ltn on the server shows 10.0.2.20:8080
echo 8080 > ${LAB_ANSWERS}/web-port
# Task 3: capture while the client fetches the home page
ip netns exec server tcpdump -i eth0 -n --immediate-mode -w ${LAB_ANSWERS}/web.pcap tcp port 8080 >/dev/null 2>&1 &
cap=\$!
sleep 1
for i in 1 2 3 4 5; do
  ip netns exec client curl -s --max-time 3 -o /dev/null http://10.0.2.20:8080/ && break
  sleep 1
done
sleep 0.5
kill -INT \$cap; wait \$cap 2>/dev/null || true
# Task 4: tcpdump -n -r mystery.pcap shows the GET line
echo /secret/${secret}.html > ${LAB_ANSWERS}/secret-page
EOS
