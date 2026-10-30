# Chapter 08 lab: solutions

Try each task before reading its solution. The commands below assume `kubectl`
defaults to `ch08-jobs` (run `make use-namespace CH=8` once). Otherwise, add
`-n ch08-jobs` to every command.

## Task 1: run `report` once

```bash
kubectl create job report --image=busybox:1.36 -- sh -c 'echo report done'
kubectl wait --for=condition=Complete job/report --timeout=120s
kubectl logs job/report
```

`kubectl create job` gives the Job `completions: 1` and `restartPolicy: Never`,
which is what this task needs. The Pod stays behind with status `Completed`, so
its logs remain available.

## Task 2: `batch`, six completions, two at a time

Imperative commands cannot set `completions` or `parallelism`, so write the YAML:

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: batch
spec:
  completions: 6
  parallelism: 2
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: busybox:1.36
          command: ["sh", "-c", "sleep 2; echo item done"]
YAML
kubectl wait --for=condition=Complete job/batch --timeout=300s
```

`kubectl get job batch` shows `6/6` in the COMPLETIONS column when it is done.

## Task 3: `fragile`, backoff limit 2

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: fragile
spec:
  backoffLimit: 2
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: busybox:1.36
          command: ["sh", "-c", "echo trying; exit 1"]
YAML
kubectl wait --for=condition=Failed job/fragile --timeout=300s
kubectl get job fragile -o jsonpath='{range .status.conditions[*]}{.type}={.status} reason={.reason}{"\n"}{end}'
```

The wait takes about 30 seconds, because the retries are spaced out. With
`backoffLimit: 2` the Job runs three Pods before it fails.

## Task 4: the `nightly-report` CronJob

```bash
kubectl create cronjob nightly-report --image=busybox:1.36 --schedule="30 2 * * *" -- sh -c 'echo nightly report'
kubectl patch cronjob nightly-report -p '{"spec":{"concurrencyPolicy":"Forbid","successfulJobsHistoryLimit":2}}'
```

`concurrencyPolicy` and `successfulJobsHistoryLimit` are CronJob fields, and the
imperative form has no flags for them, so the patch sets them.

## Task 5: `manual-run`, from the CronJob

```bash
kubectl create job manual-run --from=cronjob/nightly-report
kubectl wait --for=condition=Complete job/manual-run --timeout=120s
kubectl logs job/manual-run
```

`--from` copies the CronJob's Job template and sets the CronJob as the owner.
The output is `nightly report`.
