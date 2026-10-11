# Chapter 09 lab: solutions

Try each task before reading its solution. The commands below assume `kubectl`
defaults to `ch09-multi` (run `make use-namespace CH=9` once). Otherwise, add
`-n ch09-multi` to every command.

## Task 1: `pair`, two containers and a shared volume

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pair
spec:
  volumes:
    - name: shared
      emptyDir: {}
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh", "-c", "while true; do date >> /shared/out.txt; sleep 1; done"]
      volumeMounts:
        - name: shared
          mountPath: /shared
    - name: reader
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3; tail -f /shared/out.txt"]
      volumeMounts:
        - name: shared
          mountPath: /shared
YAML
kubectl wait --for=condition=Ready pod/pair --timeout=120s
```

Both containers mount the same volume name, `shared`, so they see the same
directory. A volume name that differs between the two containers would be a
different volume, and the reader would not see the file.

## Task 2: `setup`, an init container prepares a file

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: setup
spec:
  volumes:
    - name: work
      emptyDir: {}
  initContainers:
    - name: prepare
      image: busybox:1.36
      command: ["sh", "-c", "echo ready > /work/status.txt"]
      volumeMounts:
        - name: work
          mountPath: /work
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: work
          mountPath: /work
YAML
kubectl wait --for=condition=Ready pod/setup --timeout=120s
kubectl exec setup -c app -- cat /work/status.txt
```

## Task 3: `checked`, replace the Pod

An init container's command cannot be changed in place. Delete the Pod, then
create it again with a corrected init command:

```bash
kubectl delete pod checked
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: checked
spec:
  initContainers:
    - name: check
      image: busybox:1.36
      command: ["sh", "-c", "echo checking the config; exit 0"]
  containers:
    - name: main
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML
```

`kubectl replace --force -f` with a corrected file does the same thing in one
command. Look at `kubectl describe pod checked` before you change anything, to
see the exit code and the log of the failed init container.

## Task 4: `logged`, a native sidecar

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: logged
spec:
  volumes:
    - name: logs
      emptyDir: {}
  initContainers:
    - name: shipper
      image: busybox:1.36
      restartPolicy: Always
      command: ["sh", "-c", "touch /var/log/app/app.log; tail -F /var/log/app/app.log"]
      volumeMounts:
        - name: logs
          mountPath: /var/log/app
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "while true; do echo request handled; sleep 2; done >> /var/log/app/app.log"]
      volumeMounts:
        - name: logs
          mountPath: /var/log/app
YAML
```

The `restartPolicy: Always` on the init container is what makes it a native
sidecar. Without it, `shipper` would run once and the Pod would wait for it.

## Task 5: `debug`, a shared process namespace

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: debug
spec:
  shareProcessNamespace: true
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
    - name: helper
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML
kubectl exec debug -c helper -- ps
```

`ps` from `helper` lists two `sleep 3600` processes. Without
`shareProcessNamespace: true` it would list one.
