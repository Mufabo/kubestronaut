# Chapter 20 lab: solutions

Try each task before reading its solution. Every command runs on `cp1` as the
`vagrant` user, starting from the `cluster` snapshot. The output below is from
a real run on the lab VMs; revisions, hashes, and timestamps differ on every
run.

The `etcdctl` commands all need the same four flags. To save typing, you can
put them in a shell variable for the session:

```bash
E="--endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"
```

## Task 1: back up etcd

```bash
sudo etcdctl $E snapshot save /opt/kbook/etcd-backup.db
```

```text
{"level":"info","ts":"2026-10-15T19:01:24.248780Z","caller":"snapshot/v3_snapshot.go:83","msg":"created temporary db file","path":"/opt/kbook/etcd-backup.db.part"}
...
{"level":"info","ts":"2026-10-15T19:01:24.473217Z","caller":"snapshot/v3_snapshot.go:121","msg":"saved","path":"/opt/kbook/etcd-backup.db"}
Snapshot saved at /opt/kbook/etcd-backup.db
Server version 3.6.0
```

## Task 2: record the backup's revision

```bash
sudo etcdutl snapshot status /opt/kbook/etcd-backup.db -w table
```

```text
+----------+----------+------------+------------+---------+
|   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE | VERSION |
+----------+----------+------------+------------+---------+
| 83cc7122 |     1669 |        547 |     4.7 MB |   3.6.0 |
+----------+----------+------------+------------+---------+
```

Write the number into the file, by hand or from the JSON output:

```bash
sudo etcdutl snapshot status /opt/kbook/etcd-backup.db -w json
```

```text
{"hash":2211213602,"revision":1669,"totalKey":547,"totalSize":4665344,"version":"3.6.0"}
```

```bash
echo 1669 > /tmp/ch20-revision.txt
```

## Task 3: restore the older backup

Stop the API server first, by moving its manifest out of the directory the
kubelet watches; the kubelet then stops the Pod:

```bash
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/
sudo crictl ps --name kube-apiserver        # repeat until no container is listed
```

It takes about half a minute. Restoring over the live data does not work:

```bash
sudo etcdutl snapshot restore /opt/kbook/etcd-before.db --data-dir /var/lib/etcd
```

```text
Error: data-dir "/var/lib/etcd" not empty or could not be read
```

Restore into a new directory instead:

```bash
sudo etcdutl snapshot restore /opt/kbook/etcd-before.db --data-dir /var/lib/etcd-restore
```

```text
...
2026-10-15T19:01:25Z	info	snapshot/v3_snapshot.go:333	restored snapshot	{"path": "/opt/kbook/etcd-before.db", "wal-dir": "/var/lib/etcd-restore/member/wal", "data-dir": "/var/lib/etcd-restore", "snap-dir": "/var/lib/etcd-restore/member/snap", "initial-memory-map-size": 10737418240}
```

Then point the `etcd-data` volume at it. Edit
`/etc/kubernetes/manifests/etcd.yaml` with `sudo vim`, or with `sed`:

```bash
sudo sed -i "s|path: /var/lib/etcd$|path: /var/lib/etcd-restore|" /etc/kubernetes/manifests/etcd.yaml
sudo grep -B1 -A2 "etcd-restore" /etc/kubernetes/manifests/etcd.yaml
```

```text
  - hostPath:
      path: /var/lib/etcd-restore
      type: DirectoryOrCreate
    name: etcd-data
```

Only the hostPath changes: inside the container, etcd still uses
`--data-dir=/var/lib/etcd`, which is now the restored directory on the node.
The kubelet notices the changed manifest and recreates etcd, which takes up to
a minute or two. Check it from etcd itself, since the API server is stopped:

```bash
sudo etcdctl $E endpoint health
sudo etcdctl $E get /registry/configmaps/ch20-etcd --prefix --keys-only
```

The health check reports `is healthy`, and the keys show `legacy`, not
`current`.

## Task 4: bring the cluster back on the restored data

Start the API server again, and wait until it answers:

```bash
sudo mv /etc/kubernetes/kube-apiserver.yaml /etc/kubernetes/manifests/
kubectl get --raw /readyz; echo     # repeat until it prints ok
kubectl -n ch20-etcd get configmaps
kubectl get nodes
```

```text
NAME     DATA   AGE
legacy   1      6m6s
NAME    STATUS   ROLES           AGE    VERSION
cp1     Ready    control-plane   3d1h   v1.35.0
node1   Ready    <none>          3d1h   v1.35.0
node2   Ready    <none>          3d1h   v1.35.0
```

### Why the API server has to restart

In a first run of this lab, the API server kept running through the restore.
Afterwards, getting the ConfigMaps by name already showed the restored data,
but a list still came from the API server's cache of the old data:

```bash
kubectl -n ch20-etcd get configmap legacy current
kubectl -n ch20-etcd get configmaps
```

```text
NAME     DATA   AGE
legacy   1      5m21s
Error from server (NotFound): configmaps "current" not found
NAME               DATA   AGE
current            1      5m20s
kube-root-ca.crt   1      5m21s
```

A restore moves etcd's revision backwards, and the running API server's watch
cache did not notice. Restarting the API server (moving its manifest out and
back) fixed it, which is why Task 4 checks both a get and a list, and why the
documented order stops the API server before the restore.
