# Tier 2 environment: VirtualBox VMs with kubeadm

Three VMs on the private network `192.168.56.0/24`, built with Vagrant and
VirtualBox:

| VM | Address | Role | Memory |
|---|---|---|---|
| `cp1` | 192.168.56.10 | control plane; you work here | 2 GB |
| `node1` | 192.168.56.11 | worker | 1.5 GB |
| `node2` | 192.168.56.12 | worker | 1.5 GB |

The chapters that need real machines use it: installing a cluster with kubeadm
(18), upgrades (19), etcd backup and restore (20), node and control plane
troubleshooting (27), and most of CKS (30, 32 to 35). All versions come from
`versions.env`.

## Host requirements

- Hardware virtualization on (Intel VT-x or AMD-V, enabled in the BIOS/UEFI).
- About **5 GB of free RAM** for the three VMs, and about 30 GB of disk for the VMs and their snapshots.
- VirtualBox 7.1 or newer and Vagrant 2.4 or newer, installed on the host. On Windows, install the Windows versions (not inside WSL).
- On Windows with WSL2 or Docker Desktop, Hyper-V owns the CPU's virtualization
  extensions and VirtualBox runs on top of it. Ubuntu guests with more than one
  CPU then often hang early in boot, so **each VM gets one CPU by default**
  (kubeadm's two-CPU check is skipped on cp1). The cluster is slower but works.
  On a host without Hyper-V, build with two CPUs per VM:
  `$env:KBOOK_VM_CPUS=2` (PowerShell) or `export KBOOK_VM_CPUS=2` before `build`.

If you also run the Tier 1 kind cluster, pause it while you use the VMs:

```bash
make cluster-pause      # in WSL or your Linux/macOS shell; make cluster-resume starts it again
```

## Build the VMs once

The driver script builds the VMs and saves three snapshots. Run it from this
folder on the host:

```powershell
.\kbook-vm.ps1 build        # Windows (PowerShell)
```

```bash
./kbook-vm.sh build         # Linux and macOS
```

It takes about 45 minutes (measured on a 16-thread laptop with one CPU per VM):
about 10 for creating the VMs, then 3 to 6 per stage. When it finishes, the VMs
are running on the `cluster` snapshot.

Nodes report `Ready` before Calico has finished on a freshly joined worker, so
the build waits for the `network-ready` stage, which proves cluster DNS from a
Pod on every node, before it saves a cluster snapshot. A snapshot saved too
early keeps a worker half-configured, and Pods there cannot reach the rest of
the cluster.

| Snapshot | What it holds | Used by |
|---|---|---|
| `prereqs` | containerd, kubelet, kubeadm and kubectl at `K8S_VERSION`; no cluster | Chapter 18 (you run `kubeadm init` yourself) |
| `cluster` | a ready three-node cluster at `K8S_VERSION`, Calico CNI | most Tier 2 labs |
| `cluster-prev` | the same cluster one minor version back, at `K8S_PREV_VERSION` | Chapter 19 (you upgrade it) |

Internally there is a fourth snapshot, `os`, the common starting point the other
three branch from.

## Work on cp1

```bash
.\kbook-vm.ps1 ssh          # Windows; ./kbook-vm.sh ssh on Linux/macOS
cd /kbook                   # the whole book is mounted here
kubectl get nodes           # context kbook-vm
make test-tier2-env         # smoke test: all checks should pass
ssh node1                   # the workers, as on the exam's SSH hosts
```

Tier 2 labs run from `/kbook` on `cp1` with the usual targets (`make lab CH=19`,
`make check CH=19`). Each lab states the snapshot it needs and refuses to start
on any other.

## Reset: restore a snapshot

A Tier 2 lab cannot reset itself, because a snapshot can only be restored from
the host. `make reset` on `cp1` prints the command to run on the host instead:

```powershell
.\kbook-vm.ps1 restore cluster          # or prereqs, or cluster-prev
```

Restoring takes about two minutes and puts all three VMs back exactly as they
were when the snapshot was saved.

## Other commands

```text
kbook-vm snapshots     list the snapshots
kbook-vm halt          stop the VMs (frees the RAM; the snapshots stay)
kbook-vm up            start them again
kbook-vm status        show the VMs' state
kbook-vm destroy       delete the VMs and every snapshot; build again to recreate them
```

## How it is built

The `Vagrantfile` defines named provisioning stages, all of them `run: "never"`,
so plain `vagrant up` only boots the VMs. The driver runs them in order:

| Stage | Script | Runs on |
|---|---|---|
| `os` | `bootstrap-os.sh`: DNS fix, swap off, kernel settings, containerd, host names, SSH from cp1 to the workers | all |
| `k8s-tools` | `bootstrap-tools.sh`: kubelet, kubeadm, kubectl at an exact version, held | all |
| `cluster-init` | `bootstrap-control-plane.sh`: `kubeadm init`, Calico, the `kbook-vm` context, the lab-cluster marker | cp1 |
| `cluster-join` | `bootstrap-worker.sh`: `kubeadm join` | node1, node2 |
| `network-ready` | `bootstrap-network-ready.sh`: waits until Calico has finished on every node and cluster DNS works from a Pod on each, restarting a node's Calico if it got stuck | cp1 |
| `mark` | records the snapshot name in `/etc/kbook/snapshot` | all |

The Pod network is `10.244.0.0/16`. It must not overlap the VMs' own network,
`192.168.56.0/24`, which is why it differs from Calico's default.

The build's shared state (the join command and the lab SSH key) lives in
`envs/vagrant/.state/`, which git ignores, as it does Vagrant's `.vagrant/`.
CI cannot run VirtualBox, so this environment is tested by hand with
`make test-tier2-env` on each snapshot.
