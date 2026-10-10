# Chapter 05 lab: solutions

Try each task before reading its solution. The commands below assume
`kubectl` defaults to `ch05-deploy` (run `make use-namespace CH=5` once). If you
have not done that, add `-n ch05-deploy` to every command.

## Task 1: create `web`

```bash
kubectl create deployment web --image=nginx:1.27 --replicas=3
kubectl rollout status deployment/web
```

`rollout status` waits until all three replicas are ready, which is part of the
task. Declaratively, generate the same Deployment with `--dry-run=client -o yaml`,
save it, and `kubectl apply -f` it.

## Task 2: scale `api`

```bash
kubectl scale deployment api --replicas=5
kubectl rollout status deployment/api
```

`kubectl edit deployment api` and changing `spec.replicas` works too. Scaling
does not create a new ReplicaSet or a new revision; only changes to the Pod
template do.

## Task 3: roll out `frontend`

The container is called `web`, not `nginx`, so look before you change it:

```bash
kubectl get deployment frontend -o jsonpath='{.spec.template.spec.containers[*].name}{"\n"}'
kubectl set image deployment/frontend web=nginx:1.27
kubectl annotate deployment frontend kubernetes.io/change-cause="upgrade to 1.27" --overwrite
kubectl rollout status deployment/frontend
kubectl rollout history deployment/frontend
```

`kubectl set image deployment/frontend nginx=nginx:1.27` fails with
`unable to find container named "nginx"`. The change-cause annotation can be
added before or after the image change; it is copied to the newest revision
either way. `kubectl edit` (change the image and add the annotation in one go)
is equally valid.

## Task 4: roll back `shop`

```bash
kubectl rollout status deployment/shop --timeout=5s   # exceeded its progress deadline
kubectl rollout history deployment/shop
```

```text
REVISION  CHANGE-CAUSE
1         initial release
2         upgrade to nginx 1.27
3         try the new build
```

Revision 3 is the broken one; revision 2 is the last that worked:

```bash
kubectl rollout undo deployment/shop --to-revision=2
kubectl rollout status deployment/shop
```

Here plain `kubectl rollout undo` (one step back) would also land on revision
2, but naming the revision is the habit to build: after a second bad rollout,
"one step back" is another broken revision. The rollback becomes revision 4,
and the ReplicaSet of revision 3 scales to zero, which removes the Pods stuck in
`ImagePullBackOff`.

## Task 5: tune `cache`

```bash
kubectl patch deployment cache -p '{"spec":{"strategy":{"rollingUpdate":{"maxUnavailable":0,"maxSurge":1}}}}'
kubectl get deployment cache -o jsonpath='{.spec.strategy}{"\n"}'
```

Or `kubectl edit deployment cache` and set:

```yaml
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
```

With `maxUnavailable: 0`, an update first starts one extra Pod, waits for it to
be ready, and only then removes an old one, so capacity never drops.

## Task 6: the active ReplicaSet

```bash
kubectl get rs -l app=history
```

```text
NAME                 DESIRED   CURRENT   READY   AGE
history-578c646c76   1         1         1       2s
history-994687f59    0         0         0       4s
```

The active one has `DESIRED` above zero; the other is the kept revision 1. Your
names will differ:

```bash
kubectl get rs -l app=history -o jsonpath='{range .items[?(@.spec.replicas>0)]}{.metadata.name}{"\n"}{end}' > /tmp/ch05-rs.txt
```

The Pods tell you the same thing: their names start with the active
ReplicaSet's name, and their `pod-template-hash` label is that name's suffix.
