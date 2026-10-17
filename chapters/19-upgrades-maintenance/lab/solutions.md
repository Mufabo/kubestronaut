# Chapter 19 lab: solutions

Try each task before reading its solution. Every command runs on `cp1` as the
`vagrant` user, starting from the `cluster-prev` snapshot; `ssh node1` and
`ssh node2` reach the workers. The output below is from a real run on the lab
VMs. Pod names and timestamps differ on every run.

## Task 1: upgrade the control plane

Point apt at the 1.35 repository and look at what it offers:

```bash
sudo sed -i "s|/v1.34/|/v1.35/|" /etc/apt/sources.list.d/kubernetes.list
cat /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update -qq
apt-cache madison kubeadm | head -3
```

```text
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /
   kubeadm | 1.35.9-1.1 | https://pkgs.k8s.io/core:/stable:/v1.35/deb  Packages
   kubeadm | 1.35.8-1.1 | https://pkgs.k8s.io/core:/stable:/v1.35/deb  Packages
   kubeadm | 1.35.7-1.1 | https://pkgs.k8s.io/core:/stable:/v1.35/deb  Packages
```

The newest patch is 1.35.9, but the task asks for 1.35.0. Install exactly that
version of kubeadm, holding it again afterwards:

```bash
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.35.0-1.1
sudo apt-mark hold kubeadm
kubeadm version -o short
```

```text
v1.35.0
```

Check the plan:

```bash
sudo kubeadm upgrade plan
```

```text
...
[upgrade/versions] Cluster version: 1.34.12
[upgrade/versions] kubeadm version: v1.35.0
I1015 18:23:58.647118   20012 version.go:260] remote version is much newer: v1.37.1; falling back to: stable-1.35
[upgrade/versions] Target version: v1.35.9
[upgrade/versions] Latest version in the v1.34 series: v1.34.12

Components that must be upgraded manually after you have upgraded the control plane with 'kubeadm upgrade apply':
COMPONENT   NODE      CURRENT    TARGET
kubelet     cp1       v1.34.12   v1.35.9
kubelet     node1     v1.34.12   v1.35.9
kubelet     node2     v1.34.12   v1.35.9

Upgrade to the latest stable version:

COMPONENT                 NODE      CURRENT    TARGET
kube-apiserver            cp1       v1.34.12   v1.35.9
kube-controller-manager   cp1       v1.34.12   v1.35.9
kube-scheduler            cp1       v1.34.12   v1.35.9
kube-proxy                          1.34.12    v1.35.9
CoreDNS                             v1.12.1    v1.13.1
etcd                      cp1       3.6.5-0    3.6.6-0

You can now apply the upgrade by executing the following command:

	kubeadm upgrade apply v1.35.9

Note: Before you can perform this upgrade, you have to update kubeadm to v1.35.9.
...
```

The plan suggests the newest patch, v1.35.9. Name the version you want
explicitly:

```bash
sudo kubeadm upgrade apply -y v1.35.0
```

```text
[upgrade] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
...
[upgrade/preflight] You have chosen to upgrade the cluster version to "v1.35.0"
[upgrade/versions] Cluster version: v1.34.12
[upgrade/versions] kubeadm version: v1.35.0
[upgrade/preflight] Pulling images required for setting up a Kubernetes cluster
...
[upgrade/control-plane] Upgrading your static Pod-hosted control plane to version "v1.35.0" (timeout: 5m0s)...
[upgrade/staticpods] Writing new Static Pod manifests to "/etc/kubernetes/tmp/kubeadm-upgraded-manifests3792397203"
[upgrade/staticpods] Preparing for "etcd" upgrade
[upgrade/staticpods] Renewing etcd-server certificate
...
[upgrade/staticpods] Component "etcd" upgraded successfully!
...
[upgrade/staticpods] Component "kube-apiserver" upgraded successfully!
...
[upgrade/staticpods] Component "kube-controller-manager" upgraded successfully!
...
[upgrade/staticpods] Component "kube-scheduler" upgraded successfully!
[upgrade/control-plane] The control plane instance for this node was successfully upgraded!
...
[addons] Applied essential addon: CoreDNS
[addons] Applied essential addon: kube-proxy
...

[upgrade] SUCCESS! A control plane node of your cluster was upgraded to "v1.35.0".

[upgrade] Now please proceed with upgrading the rest of the nodes by following the right order.
```

If it stops in its preflight with `[ERROR CreateJob]: Job
"upgrade-health-check-..." ... did not complete in 15s` instead, the cluster was
too busy to run kubeadm's health-check Job in time (the lab VMs have one CPU
each). Nothing has changed yet; run the same command again.

The whole run takes a few minutes. One `E1015 ... request canceled` line in the
middle is normal: it appears while etcd restarts. The old manifests are backed
up under `/etc/kubernetes/tmp/kubeadm-backup-manifests-*`.

## Task 2: upgrade cp1's kubelet

`kubectl get nodes` still shows v1.34.12 everywhere, because its `VERSION`
column is the kubelet's version. Drain `cp1`, then upgrade the kubelet and
kubectl:

```bash
kubectl drain cp1 --ignore-daemonsets
```

```text
node/cp1 cordoned
Warning: ignoring DaemonSet-managed Pods: kube-system/calico-node-wgphd, kube-system/kube-proxy-kxz8j
evicting pod kube-system/coredns-66bc5c9577-mbrcf
evicting pod kube-system/calico-kube-controllers-855c4cc49d-djcx7
error when evicting pods/"calico-kube-controllers-855c4cc49d-djcx7" -n "kube-system" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod kube-system/calico-kube-controllers-855c4cc49d-djcx7
pod/coredns-66bc5c9577-mbrcf evicted
pod/calico-kube-controllers-855c4cc49d-djcx7 evicted
node/cp1 drained
```

Calico ships a PodDisruptionBudget for its controller; drain waited for it and
retried, as the chapter describes.

```bash
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.35.0-1.1 kubectl=1.35.0-1.1
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
kubectl wait --for=condition=Ready node/cp1 --timeout=300s
kubectl uncordon cp1
kubectl get nodes
```

```text
node/cp1 condition met
node/cp1 uncordoned
NAME    STATUS   ROLES           AGE   VERSION
cp1     Ready    control-plane   3d    v1.35.0
node1   Ready    <none>          3d    v1.34.12
node2   Ready    <none>          3d    v1.34.12
```

The new kubelet restarts the control plane's static Pods, so the API server can
go away for a minute **after** this point. In the run above, the next command
failed:

```text
error: Get "https://192.168.56.10:6443/api/v1/nodes/node1": dial tcp 192.168.56.10:6443: connect: connection refused - error from a previous attempt: unexpected EOF
```

Wait until `kubectl get nodes` answers again, and repeat any command that
failed, before you go on.

## Task 3: upgrade node1

Drain the worker. `debug` has no controller, so the drain needs `--force` and
`debug` is gone afterwards; `web` is evicted one Pod at a time, as its
PodDisruptionBudget allows:

```bash
kubectl drain node1 --ignore-daemonsets --delete-emptydir-data --force
```

Then, on the worker, the same repository switch and packages, with
`kubeadm upgrade node` in between:

```bash
ssh node1
sudo sed -i "s|/v1.34/|/v1.35/|" /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update -qq
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt-get install -y kubeadm=1.35.0-1.1
sudo kubeadm upgrade node
```

```text
[upgrade] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[upgrade] Use 'kubeadm init phase upload-config kubeadm --config your-config-file' to re-upload it.
[upgrade/preflight] Running pre-flight checks
[upgrade/preflight] Skipping prepull. Not a control plane node.
[upgrade/control-plane] Skipping phase. Not a control plane node.
[upgrade/kubeconfig] Skipping phase. Not a control plane node.
...
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[upgrade/kubelet-config] The kubelet configuration for this node was successfully upgraded!
[upgrade/addon] Skipping the addon/coredns phase. Not a control plane node.
[upgrade/addon] Skipping the addon/kube-proxy phase. Not a control plane node.
...
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
```

```bash
sudo apt-get install -y kubelet=1.35.0-1.1 kubectl=1.35.0-1.1
sudo apt-mark hold kubeadm kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
exit
```

Back on `cp1`:

```bash
kubectl wait --for=condition=Ready node/node1 --timeout=300s
kubectl uncordon node1
kubectl get nodes node1
```

## Task 4: upgrade node2

The same steps as Task 3, with `node2` in place of `node1`. Whether you
uncordon `node2` at the end depends on Task 5; leaving it cordoned saves a
step.

## Task 5: take node2 out of service

If you uncordoned `node2`, drain it again; the drain cordons it:

```bash
kubectl drain node2 --ignore-daemonsets --delete-emptydir-data --force
kubectl get pods -A -o wide --field-selector spec.nodeName=node2
kubectl -n ch19-upgrade get deployment web
kubectl -n ch19-upgrade get pdb web
```

Only `calico-node` and `kube-proxy`, both from DaemonSets, remain on `node2`.
Both `web` replicas now run on the other nodes, and the PodDisruptionBudget is
the one the lab created. If a drain hangs on `web`, it is waiting for a
replacement Pod to become ready; deleting the budget would make the drain
faster, but it would also break this task.
