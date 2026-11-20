# The Tier 0 lab environment for Part V: one container with every networking
# tool the book uses. Readers build whole networks inside it out of network
# namespaces, so nothing ever touches the host's own networking.
#
# Built by `make netlab` (tools/netlab.sh). The base image is pinned in
# versions.env; bump NETLAB_IMAGE there whenever this file changes.
ARG BASE_IMAGE=debian:13.7-slim
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

# man pages are stripped from Debian slim images; keep them for this image
# because reading `man ip-route` is a skill the book teaches.
RUN rm -f /etc/dpkg/dpkg.cfg.d/docker /etc/dpkg/dpkg.cfg.d/excludes 2>/dev/null; \
    apt-get update && apt-get install -y --no-install-recommends \
      iproute2 iputils-ping iputils-arping iputils-tracepath traceroute mtr-tiny \
      tcpdump tshark iptables nftables conntrack ethtool \
      dnsmasq-base bind9-dnsutils curl openssl ca-certificates socat netcat-openbsd \
      python3 ipcalc jq iperf3 procps psmisc less vim-tiny nano man-db manpages \
      bash-completion tini \
    && rm -rf /var/lib/apt/lists/*

# Helpers live in /opt/netlab, which tools/netlab.sh mounts read-only from
# envs/netlab/rootfs. These wrappers make them available on PATH and in every
# interactive shell, including shells started inside a namespace.
RUN for b in on netmap topo; do \
      printf '#!/bin/sh\nexec bash /opt/netlab/bin/%s "$@"\n' "$b" > /usr/local/bin/$b; \
      chmod 755 /usr/local/bin/$b; done \
    && printf '#!/bin/sh\nexec python3 /opt/netlab/bin/labhttp "$@"\n' > /usr/local/bin/labhttp \
    && chmod 755 /usr/local/bin/labhttp \
    && echo '[ -f /opt/netlab/bashrc ] && . /opt/netlab/bashrc' >> /etc/bash.bashrc \
    && mkdir -p /root/answers /var/log/netlab /run/netlab /etc/netlab

WORKDIR /root
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sleep", "infinity"]
