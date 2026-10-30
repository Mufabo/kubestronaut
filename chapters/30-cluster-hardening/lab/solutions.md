# Chapter 30 lab: solutions

Every command runs on `cp1` unless it starts with `ssh`. Each task has other valid
answers; the checks look at the result.

## Task 1: Pass kube-bench's node checks on node2

```bash
ssh node2
sudo kube-bench run --targets node --benchmark cis-1.12 2>/dev/null | grep -E '^\[FAIL\]'
```

```text
[FAIL] 4.1.1 Ensure that the kubelet service file permissions are set to 600 or more restrictive (Automated)
[FAIL] 4.1.9 If the kubelet config.yaml configuration file is being used validate permissions set to 600 or more restrictive (Automated)
```

Find the files the audits check (`--json`, field `audit`), then fix their mode:

```bash
sudo chmod 600 /lib/systemd/system/kubelet.service /var/lib/kubelet/config.yaml
sudo kube-bench run --targets node --benchmark cis-1.12 2>/dev/null | grep 'checks FAIL'
exit
```

The kubelet runs as root and still reads both. Changing only the kubeadm drop-in in
`/usr/lib/systemd/system/kubelet.service.d/` does not satisfy 4.1.1.

## Task 2: Turn off profiling on the control plane

```bash
sudo mkdir -p /root/manifests-backup
sudo cp /etc/kubernetes/manifests/kube-*.yaml /root/manifests-backup/
sudo vim /etc/kubernetes/manifests/kube-apiserver.yaml
```

Add one line to `command` (the same in `kube-controller-manager.yaml` and
`kube-scheduler.yaml`):

```yaml
    - --profiling=false
```

```bash
sudo crictl ps --name 'kube-(apiserver|controller-manager|scheduler)'
kubectl -n kube-system get pods -l tier=control-plane
sudo kube-bench run --targets master --benchmark cis-1.12 --check 1.2.15,1.3.2,1.4.1 2>/dev/null | grep -E '^\[(PASS|FAIL)\]'
```

Wait for each component to restart before checking: the kubelet restarts a static Pod
when its manifest changes, and the controller manager and scheduler lose their leader
lease while the API server is down.

## Task 3: Harden node1's kubelet

```bash
ssh node1
sudo vim /var/lib/kubelet/config.yaml
```

Set:

```yaml
authentication:
  anonymous:
    enabled: false
authorization:
  mode: Webhook
```

and delete the line `readOnlyPort: 10255` (or set it to `0`). Then:

```bash
sudo systemctl restart kubelet
exit
curl -sk https://node1:10250/pods                       # Unauthorized
curl -s -m 3 http://node1:10255/pods; echo rc=$?        # rc=7: nothing listens
kubectl get --raw /api/v1/nodes/node1/proxy/configz | head -c 300
```

The `configz` endpoint shows the configuration the kubelet actually runs with, through
the API server.

## Task 4: Keep only the genuine kubectl

```bash
cd /opt/ch30
curl -fsSLO https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl.sha512
for f in kubectl-*; do echo "$(cat kubectl.sha512)  $f" | sha512sum --check; done
sudo rm kubectl.sha512 <the two files that FAILED>
ls /opt/ch30
```

One file fails because one byte was added, the other because it is the previous
release's `kubectl`: same name, a different binary. Only the checksum tells them apart.

## Task 5: Keep Pods away from the metadata endpoint

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-metadata
  namespace: ch30-apps
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 169.254.169.254/32
```

```bash
kubectl -n ch30-apps exec client -- wget -qO- -T 3 http://web | head -4
```

The VMs have no metadata endpoint, but the policy is the same as on a cloud provider's
nodes. A policy that listed only allowed destinations would also have to allow DNS;
this one allows everything except one address, so DNS and Services keep working.
