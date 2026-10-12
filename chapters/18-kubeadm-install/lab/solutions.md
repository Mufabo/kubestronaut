# Chapter 18 lab: solutions

Try each task before reading its solution. Every command runs on `cp1` as the
`vagrant` user, starting from the `prereqs` snapshot. The output below is from
a real run on the lab VMs; tokens and hashes are replaced by `<token>` and
`<hash>`.

## Task 1: initialize the control plane

```bash
sudo kubeadm init --apiserver-advertise-address=192.168.56.10 \
  --pod-network-cidr=10.244.0.0/16 --kubernetes-version=v1.35.0 \
  --ignore-preflight-errors=NumCPU
```

The output walks through the phases from the chapter and ends like this:

```text
[mark-control-plane] Marking the node cp1 as control-plane by adding the taints [node-role.kubernetes.io/control-plane:NoSchedule]
[bootstrap-token] Using token: <token>
...
[addons] Applied essential addon: CoreDNS
[addons] Applied essential addon: kube-proxy

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 192.168.56.10:6443 --token <token> \
	--discovery-token-ca-cert-hash sha256:<hash>
```

`--apiserver-advertise-address` matters here because each VM has two network
interfaces: a NAT one (the default route, the same address on every VM) and the
private `192.168.56.0/24` one the nodes share. `--kubernetes-version` keeps
kubeadm from looking up the newest release online, and the NumCPU flag is only
needed because the lab VMs have one CPU.

If `init` fails halfway (a typo in a flag, for example), clean up with
`sudo kubeadm reset -f` and run it again.

## Task 2: kubectl for your user

```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl config get-contexts
```

```text
CURRENT   NAME                          CLUSTER      AUTHINFO           NAMESPACE
*         kubernetes-admin@kubernetes   kubernetes   kubernetes-admin
```

```bash
kubectl config rename-context kubernetes-admin@kubernetes kbook-vm
kubectl get nodes
```

```text
Context "kubernetes-admin@kubernetes" renamed to "kbook-vm".
NAME   STATUS     ROLES           AGE   VERSION
cp1    NotReady   control-plane   7s    v1.35.0
```

`NotReady` is expected: there is no Pod network yet.

## Task 3: install the Pod network

Download the manifest, then uncomment the pool setting and give it the Pod
network from Task 1:

```bash
curl -fsSL https://raw.githubusercontent.com/projectcalico/calico/v3.32.2/manifests/calico.yaml -o calico.yaml
grep -n -A1 "CALICO_IPV4POOL_CIDR" calico.yaml
```

```text
7633:            # - name: CALICO_IPV4POOL_CIDR
7634-            #   value: "192.168.0.0/16"
```

```bash
sed -i -e 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' \
  -e 's|#   value: "192.168.0.0/16"|  value: "10.244.0.0/16"|' calico.yaml
grep -n -A1 "CALICO_IPV4POOL_CIDR" calico.yaml
```

```text
7633:            - name: CALICO_IPV4POOL_CIDR
7634-              value: "10.244.0.0/16"
```

Editing the file in `vim` works just as well; keep the indentation of the
surrounding `env` entries. Then apply it and wait:

```bash
kubectl apply -f calico.yaml
kubectl -n kube-system rollout status daemonset/calico-node --timeout=600s
kubectl get nodes
```

```text
Waiting for daemon set "calico-node" rollout to finish: 0 of 1 updated pods are available...
daemon set "calico-node" successfully rolled out
NAME   STATUS   ROLES           AGE   VERSION
cp1    Ready    control-plane   82s   v1.35.0
```

Calico reads `CALICO_IPV4POOL_CIDR` only when it creates its first IP pool. If
you applied the manifest with the wrong range, changing the variable later does
not change the pool; the quickest fix in the lab is restoring `prereqs` and
starting over.

## Task 4: join the workers

Create a fresh join command on `cp1` and run it as root on each worker:

```bash
sudo kubeadm token create --print-join-command
```

```text
kubeadm join 192.168.56.10:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

```bash
ssh node1
sudo kubeadm join 192.168.56.10:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
exit
```

```text
[preflight] Running pre-flight checks
[preflight] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
...
[kubelet-start] Starting the kubelet
[kubelet-check] Waiting for a healthy kubelet at http://127.0.0.1:10248/healthz. This can take up to 4m0s
[kubelet-check] The kubelet is healthy after 1.323030307s
[kubelet-start] Waiting for the kubelet to perform the TLS Bootstrap

This node has joined the cluster:
* Certificate signing request was sent to apiserver and a response was received.
* The Kubelet was informed of the new secure connection details.

Run 'kubectl get nodes' on the control-plane to see this node join the cluster.
```

Repeat on `node2`. A joined node is `NotReady` until Calico has started on it,
which takes a minute or two on these VMs:

```bash
kubectl get nodes -o wide
```

```text
NAME    STATUS     ROLES           AGE     VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
cp1     Ready      control-plane   2m32s   v1.35.0   192.168.56.10   <none>        Ubuntu 22.04.3 LTS   5.15.0-91-generic   containerd://2.2.1
node1   Ready      <none>          59s     v1.35.0   192.168.56.11   <none>        Ubuntu 22.04.3 LTS   5.15.0-91-generic   containerd://2.2.1
node2   NotReady   <none>          48s     v1.35.0   192.168.56.12   <none>        Ubuntu 22.04.3 LTS   5.15.0-91-generic   containerd://2.2.1
```

`kubectl -n kube-system get pods -o wide` shows why: `node2`'s `calico-node`
Pod is still in `Init:0/3`. Wait until every node is `Ready`
(`kubectl wait --for=condition=Ready node --all --timeout=600s`).

## Task 5: label the workers

```bash
kubectl label node node1 node2 node-role.kubernetes.io/worker=
kubectl get nodes
```

```text
node/node1 labeled
node/node2 labeled
NAME    STATUS     ROLES           AGE     VERSION
cp1     Ready      control-plane   2m33s   v1.35.0
node1   Ready      worker          60s     v1.35.0
node2   NotReady   worker          49s     v1.35.0
```

The `ROLES` column is only a display of `node-role.kubernetes.io/<role>`
labels; it has no effect on scheduling. (In this run `node2` was still waiting
for Calico; it becomes `Ready` shortly after.)

## Explore what you built

```bash
sudo kubeadm certs check-expiration
sudo ls /etc/kubernetes /etc/kubernetes/manifests
sudo kubeadm token list
```

The certificates expire in one year (`364d`), the three CAs in ten (`9y`);
`/etc/kubernetes/manifests` holds the four static Pod manifests; and the token
list shows the token `init` created plus the ones `token create` added, each
valid for 24 hours.
