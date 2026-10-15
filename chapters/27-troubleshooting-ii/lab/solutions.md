# Chapter 27 lab: solutions

Try each task before reading its solution: finding the fault is the point of
the lab. Every command runs on `cp1` as the `vagrant` user; `ssh node1` and
`ssh node2` reach the workers. The output below is from a real run on the lab
VMs; names, times, and serial numbers differ on every run.

Right after `make lab`, the overview shows all three faults at once:

```bash
kubectl get nodes
kubectl -n kube-system get pods
kubectl -n ch27-trouble get pods
```

```text
NAME    STATUS     ROLES           AGE    VERSION
cp1     Ready      control-plane   3d1h   v1.35.0
node1   NotReady   <none>          3d1h   v1.35.0
node2   NotReady   <none>          3d1h   v1.35.0
NAME                                       READY   STATUS             RESTARTS      AGE
calico-kube-controllers-7bbf4599f5-h7762   1/1     Running            0             3d1h
calico-node-pgrnp                          0/1     Running            0             3d1h
...
kube-scheduler-cp1                         0/1     CrashLoopBackOff   2 (19s ago)   37s
NAME                 READY   STATUS    RESTARTS   AGE
web-7dbf7cc5-d2mck   0/1     Pending   0          44s
web-7dbf7cc5-frjql   0/1     Pending   0          44s
```

## Task 1: bring node1 back

The node's conditions are all `Unknown`: the control plane does not hear from
its kubelet.

```bash
kubectl describe node node1 | sed -n "/^Conditions:/,/^Addresses:/p"
ssh node1 systemctl status kubelet --no-pager | head -6
```

```text
...
  Ready                Unknown   Thu, 15 Oct 2026 19:23:22 +0000   Thu, 15 Oct 2026 19:24:16 +0000   NodeStatusUnknown   Kubelet stopped posting node status.
...
○ kubelet.service - kubelet: The Kubernetes Node Agent
     Loaded: loaded (/lib/systemd/system/kubelet.service; disabled; vendor preset: enabled)
    Drop-In: /usr/lib/systemd/system/kubelet.service.d
             └─10-kubeadm.conf
     Active: inactive (dead)
       Docs: https://kubernetes.io/docs/
```

Stopped (`inactive (dead)`) and `disabled`, so it would not start at boot
either. One command fixes both:

```bash
ssh node1 sudo systemctl enable --now kubelet
```

```text
Created symlink /etc/systemd/system/multi-user.target.wants/kubelet.service → /lib/systemd/system/kubelet.service.
```

## Task 2: bring node2 back

Here the kubelet runs:

```bash
ssh node2 systemctl status kubelet --no-pager | head -6
```

```text
● kubelet.service - kubelet: The Kubernetes Node Agent
     Loaded: loaded (/lib/systemd/system/kubelet.service; enabled; vendor preset: enabled)
    Drop-In: /usr/lib/systemd/system/kubelet.service.d
             └─10-kubeadm.conf
     Active: active (running) since Thu 2026-10-15 19:23:31 UTC; 50s ago
       Docs: https://kubernetes.io/docs/
```

So the answer is in its log:

```bash
ssh node2 sudo journalctl -u kubelet --no-pager -n 200 | grep -m3 -E "connect|refused"
```

```text
Oct 15 19:24:02 node2 kubelet[13432]: E1015 19:24:02.715355   13432 reconstruct.go:188] "Failed to get Node status to reconstruct device paths" err="Get \"https://192.168.56.10:6444/api/v1/nodes/node2\": dial tcp 192.168.56.10:6444: connect: connection refused"
...
```

It calls port 6444. Compare its kubeconfig with yours:

```bash
ssh node2 sudo grep server: /etc/kubernetes/kubelet.conf
grep server: ~/.kube/config
```

```text
    server: https://192.168.56.10:6444
    server: https://192.168.56.10:6443
```

Fix the port and restart the kubelet:

```bash
ssh node2 "sudo sed -i 's|:6444|:6443|' /etc/kubernetes/kubelet.conf && sudo systemctl restart kubelet"
kubectl get nodes
```

```text
NAME    STATUS   ROLES           AGE    VERSION
cp1     Ready    control-plane   3d1h   v1.35.0
node1   Ready    <none>          3d1h   v1.35.0
node2   Ready    <none>          3d1h   v1.35.0
```

## Task 3: get web scheduled

The nodes are back, but `web` is still `Pending`, with no events at all:
nothing has looked at these Pods.

```bash
kubectl -n ch27-trouble describe pod -l app=web | grep -A1 "^Events:"
kubectl -n kube-system get pod kube-scheduler-cp1
kubectl -n kube-system logs kube-scheduler-cp1 --tail=5
```

```text
Events:                      <none>
...
NAME                 READY   STATUS             RESTARTS      AGE
kube-scheduler-cp1   0/1     CrashLoopBackOff   2 (27s ago)   45s
I1015 19:23:58.929572       1 serving.go:386] Generated self-signed cert in-memory
E1015 19:23:58.930289       1 run.go:72] "command failed" err="stat /etc/kubernetes/scheduler.config: no such file or directory"
```

The same log is available without the API server, through the runtime:
`sudo crictl ps -a --name kube-scheduler`, then `sudo crictl logs` with the ID
of an exited container. Compare the manifest with the files that exist:

```bash
sudo grep -n kubeconfig /etc/kubernetes/manifests/kube-scheduler.yaml
sudo ls /etc/kubernetes/*.conf
```

```text
13:    - --authentication-kubeconfig=/etc/kubernetes/scheduler.conf
14:    - --authorization-kubeconfig=/etc/kubernetes/scheduler.conf
16:    - --kubeconfig=/etc/kubernetes/scheduler.config
59:      name: kubeconfig
71:    name: kubeconfig
/etc/kubernetes/admin.conf
/etc/kubernetes/controller-manager.conf
/etc/kubernetes/kubelet.conf
/etc/kubernetes/scheduler.conf
/etc/kubernetes/super-admin.conf
```

Fix line 16 (with `sudo vim`, or `sed`), and let the kubelet restart the Pod:

```bash
sudo sed -i "s|scheduler.config$|scheduler.conf|" /etc/kubernetes/manifests/kube-scheduler.yaml
kubectl -n ch27-trouble get pods -o wide        # repeat until both are Running
```

```text
NAME                 READY   STATUS    RESTARTS   AGE    IP               NODE    NOMINATED NODE   READINESS GATES
web-7dbf7cc5-d2mck   1/1     Running   0          114s   10.244.166.131   node1   <none>           <none>
web-7dbf7cc5-frjql   1/1     Running   0          114s   10.244.104.2     node2   <none>           <none>
```

It took about a minute: the kubelet waits out the crash back-off before it
starts the corrected container.

## Task 4: when does the cluster CA expire?

```bash
sudo openssl x509 -enddate -noout -in /etc/kubernetes/pki/ca.crt
```

```text
notAfter=Oct  9 17:43:57 2036 GMT
```

```bash
sudo openssl x509 -enddate -noout -in /etc/kubernetes/pki/ca.crt | cut -d= -f2 > /tmp/ch27-ca-expiry.txt
cat /tmp/ch27-ca-expiry.txt
```

```text
Oct  9 17:43:57 2036 GMT
```

Keep the two spaces before a one-digit day: that is how `openssl` prints it.

## Task 5: renew the API server certificate

Note the current certificate, renew it, and look again:

```bash
sudo openssl x509 -enddate -noout -serial -in /etc/kubernetes/pki/apiserver.crt
sudo kubeadm certs renew apiserver
sudo openssl x509 -enddate -noout -serial -in /etc/kubernetes/pki/apiserver.crt
```

```text
notAfter=Oct 12 17:43:57 2027 GMT
serial=11D39BB0A26FB84A
[renew] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[renew] Use 'kubeadm init phase upload-config kubeadm --config your-config-file' to re-upload it.

certificate for serving the Kubernetes API renewed
notAfter=Oct 15 19:25:28 2027 GMT
serial=0FF61E78DD54A181
```

A new serial number, and one year from today. Now check what the API server
actually serves:

```bash
openssl s_client -connect 192.168.56.10:6443 </dev/null 2>/dev/null | openssl x509 -noout -serial -enddate
```

```text
serial=0FF61E78DD54A181
notAfter=Oct 15 19:25:28 2027 GMT
```

The served serial matches the file: the API server reloaded its serving
certificate by itself. If it showed the old serial, restart the API server by
moving its manifest out of the directory and back:

```bash
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/
sudo crictl ps --name kube-apiserver          # repeat until nothing is listed (about 30s)
sudo mv /etc/kubernetes/kube-apiserver.yaml /etc/kubernetes/manifests/
kubectl get --raw /readyz; echo               # repeat until it prints ok (about 10s)
```

The same restart is what the controller manager and the scheduler need after
their kubeconfig certificates are renewed (`kubeadm certs renew all`), because
they read those only at start.
