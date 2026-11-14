#!/usr/bin/env bash
# Stage "ha-hosts", cp1 only (KBOOK_HA=1): cp1's snapshots can be older than the
# HA VMs, so give it their names in /etc/hosts and let the vagrant user ssh to
# them without a prompt, as it does to node1 and node2. Runs as root.
set -euo pipefail
sed -i '/# kbook-lab$/d' /etc/hosts
while read -r line; do
  [[ -n "$line" ]] && echo "${line} # kbook-lab" >> /etc/hosts
done <<<"$HOSTS"
cat > /home/vagrant/.ssh/config <<SSHCONFIG
Host node1 node2 cp1 cp2 cp3 lb
  StrictHostKeyChecking accept-new
  UserKnownHostsFile /home/vagrant/.ssh/known_hosts
SSHCONFIG
chown vagrant:vagrant /home/vagrant/.ssh/config
chmod 600 /home/vagrant/.ssh/config
