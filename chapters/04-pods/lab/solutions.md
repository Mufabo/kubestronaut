# Chapter 04 lab: solutions

Try each task before reading its solution. The commands below assume
`kubectl` defaults to `ch04-pods` (run `make use-namespace CH=4` once). If you
have not done that, add `-n ch04-pods` to every command.

## Task 1: create `web`

```bash
kubectl run web --image=nginx:1.27 --labels=app=web --port=80
```

`kubectl run` creates a single Pod. `--port` sets `containerPort`, which is
documentation for humans and tools; it does not open or close anything.

## Task 2: fix `broken`

```bash
kubectl describe pod broken          # Events: Failed to pull image ... not found
kubectl set image pod/broken web=nginx:1.27
```

Alternatives: `kubectl edit pod broken`, or `kubectl patch`. A Pod's container
image is one of the few fields you can change in place; the kubelet restarts the
container with the new image. Most other Pod spec fields are immutable, in which
case you must delete and recreate the Pod
(`kubectl replace --force -f pod.yaml`).

## Task 3: find the code in the logs

```bash
kubectl logs logger | grep activation-code
kubectl logs logger | grep -m1 'activation-code=' | cut -d= -f2 > /tmp/ch04-code.txt
```

## Task 4: requests and limits

Resource settings have no dedicated `kubectl run` flags in current versions,
so generate a Pod skeleton and add the `resources` block, or write it by hand:

```bash
kubectl run limited --image=nginx:1.27 --dry-run=client -o yaml > limited.yaml
# edit limited.yaml: add the resources block below under the container
kubectl apply -f limited.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: limited
spec:
  containers:
    - name: limited
      image: nginx:1.27
      resources:
        requests: {cpu: 100m, memory: 64Mi}
        limits: {cpu: 200m, memory: 128Mi}
```

## Task 5: a Pod that runs once

```bash
kubectl run once --image=busybox:1.36 --restart=Never -- echo hello
kubectl logs once
```

With the default `restartPolicy: Always`, a container that exits (even with
code 0) is restarted forever. `Never` lets the Pod finish as `Succeeded`.
