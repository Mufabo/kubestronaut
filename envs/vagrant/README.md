# Tier 2 environment: VirtualBox VMs with kubeadm

Three VMs: `cp1` (control plane), `node1` and `node2` (workers), on the private
network `192.168.56.0/24`. The versions come from `versions.env`.

**Status: untested.** CI cannot run VirtualBox, so these files are not yet proven.
Run the steps below on your host and report what happens.

## Host requirements

- Hardware virtualization on (Intel VT-x or AMD-V, enabled in the BIOS/UEFI).
- About 8 GB of RAM free for the three VMs (2.5 GB each, plus the host).
- VirtualBox (virtualbox.org) and Vagrant (developer.hashicorp.com/vagrant), both on Windows.

## Bring the cluster up

```bash
cd envs/vagrant
vagrant up                 # about 10 to 15 minutes the first time
vagrant ssh cp1 -c "kubectl get nodes -o wide"
```

Expect three nodes, all `Ready`, with the Kubernetes version from `versions.env`.

## Reset and clean up

```bash
vagrant provision cp1      # re-run the control-plane bootstrap
vagrant destroy -f         # remove the VMs; the next `vagrant up` builds them again
```

The shared state (`envs/vagrant/.state/join.sh`) is git-ignored. Snapshot-based reset
for the labs is not built yet.
