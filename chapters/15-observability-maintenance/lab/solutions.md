# Chapter 15 lab: solutions

Try each task before reading its solution. The commands below assume `kubectl`
is pointed at the lab namespace with `-n ch15-observe`. Pass the flag explicitly,
because the lab does not change your default namespace.

## Task 1: the crash message

```bash
kubectl -n ch15-observe logs crasher --previous
kubectl -n ch15-observe logs crasher
```

Find the line that contains `fatal`, and save it, without any other text, to
`/tmp/ch15-crash.txt`:

```bash
kubectl -n ch15-observe logs crasher | grep -m1 fatal > /tmp/ch15-crash.txt
```

`--previous` asks for the last terminated container. On the lab's kind node that
log is often already gone, and `kubectl` then prints `unable to retrieve container
logs` with exit status 0. Read the current logs in that case: the failing run
prints the same line.

## Task 2: replace `crasher` with the setting

The environment of a running container cannot change, so delete the Pod and
create it again with `DATABASE_URL` set:

```bash
kubectl -n ch15-observe delete pod crasher
cat <<'YAML' | kubectl -n ch15-observe apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: crasher
spec:
  containers:
    - name: crasher
      image: busybox:1.36
      env:
        - name: DATABASE_URL
          value: postgres://db:5432/shop
      command:
        - sh
        - -c
        - |
          if [ -z "$DATABASE_URL" ]; then
            echo "fatal: missing config DATABASE_URL"
            exit 3
          fi
          echo "connected"
          sleep 3600
YAML
kubectl -n ch15-observe wait --for=condition=Ready pod/crasher --timeout=180s
```

The Pod runs `echo "connected"` and then sleeps, so it stays up.

## Task 3: the last lines of every checkout Pod

```bash
kubectl -n ch15-observe logs -l app=checkout --tail=3 > /tmp/ch15-checkout.log
```

`-l app=checkout` reads every Pod with that label, and `--tail=3` takes three lines
from each one. With two Pods, the file holds six lines.

## Task 4: the annotation on the Pod template

```bash
kubectl -n ch15-observe patch deployment checkout -p '{"spec":{"template":{"metadata":{"annotations":{"observability.example.com/scrape":"true"}}}}}'
kubectl -n ch15-observe rollout status deployment/checkout
```

The template becomes the Pods' metadata, so the patch changes the Pods, and the
rollout replaces them. A patch to the Deployment's own metadata would not.

## Task 5: the PodDisruptionBudget at the served version

```bash
kubectl api-resources --api-group=policy
```

The output shows `policy/v1`. Create the budget with that version:

```bash
cat <<'YAML' | kubectl -n ch15-observe apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: checkout-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: checkout
YAML
```

## Why these checks accept any correct method

Each check reads what is stored or running: the file contents, the Pod's
environment and readiness, the Deployment's Pod template, and the PodDisruptionBudget's
stored version and fields. You can produce the files with any command that gives
the same content, and the checks do not care how.
