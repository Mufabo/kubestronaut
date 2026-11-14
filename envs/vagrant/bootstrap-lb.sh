#!/usr/bin/env bash
# Stage "lb", the lb VM only (KBOOK_HA=1): HAProxy as the load balancer in front of
# the API servers of cp1, cp2, and cp3 for Chapter 18's highly available control
# plane. It passes TCP through (TLS ends at the API servers) and takes a server out
# while its /readyz does not answer 200. Runs as root.
# BACKENDS: "name:ip name:ip ..." of the control plane nodes.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq haproxy

servers=""
for backend in $BACKENDS; do
  servers+="    server ${backend%%:*} ${backend#*:}:6443"$'\n'
done
cat > /etc/haproxy/haproxy.cfg <<CFG
global
    log /dev/log local0
    maxconn 2000

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5s
    timeout client 1h
    timeout server 1h

frontend kube-apiserver
    bind *:6443
    default_backend control-plane

backend control-plane
    option httpchk GET /readyz
    http-check expect status 200
    default-server check check-ssl verify none inter 3s fall 3 rise 2
${servers}
CFG
haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null
systemctl enable haproxy >/dev/null 2>&1
systemctl restart haproxy
