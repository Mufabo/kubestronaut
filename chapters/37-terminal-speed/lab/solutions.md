# Chapter 37 lab: solutions

These drills are timed in the book's own terms: note how long each one takes you, and which
step cost the most. Commands pass `-n ch37-drill` explicitly.

## Task 1: a generated Deployment

```bash
kubectl -n ch37-drill create deployment speed --image=nginx:1.27
kubectl -n ch37-drill scale deployment speed --replicas=3
```

`create deployment` generates the object, and `scale` changes only the replica count.
Check the ready count with `kubectl -n ch37-drill get deploy speed`.

## Task 2: a generated Job, saved and applied

```bash
kubectl -n ch37-drill create job count --image=busybox:1.36 --dry-run=client -o yaml -- sh -c 'echo 1' > /tmp/ch37/count-job.yaml
kubectl -n ch37-drill apply -f /tmp/ch37/count-job.yaml
kubectl -n ch37-drill wait --for=condition=Complete job/count --timeout=120s
```

The redirect keeps the manifest, so you can check it before you apply it.

## Task 3: the restarted Pods, filtered

```bash
kubectl -n ch37-drill get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].restartCount}{"\n"}{end}' \
  | awk '$2 > 0 {print $1}' > /tmp/ch37/restarted.txt
```

The same result with `jq`:

```bash
kubectl -n ch37-drill get pods -o json \
  | jq -r '.items[] | select(.status.containerStatuses[0].restartCount > 0) | .metadata.name' \
  > /tmp/ch37/restarted.txt
```

Only `flaky` has restarted. The two steady Pods keep a restart count of 0.

## Task 4: a changed copy

```bash
cp /tmp/ch37/base-deploy.yaml /tmp/ch37/scaled.yaml
yq -i '.spec.replicas = 5' /tmp/ch37/scaled.yaml
```

`yq -i` edits the file in place. The base file stays at 2 replicas, and the cluster is not
touched.

## Clean up

`make teardown CH=37` removes the Namespace, the answer files in `/tmp/ch37`, and restores
your kubectl context.
