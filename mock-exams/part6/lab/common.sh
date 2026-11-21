# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # variables come from the sourcing script and lab.env
# Shared helpers for the Part VI simulator. Sourced by the lab scripts.

STATE="${here}/.state"
CTX=p6-a

# first_cni_conf <node>   the configuration file the runtime uses
first_cni_conf() {
  docker exec "$1" sh -c 'ls -1 /etc/cni/net.d 2>/dev/null | grep -E "\.(conf|conflist|json)$" | sort | head -n1' 2>/dev/null
}
