# Mock exam Part II: solutions

Read these only after `make mock-score EXAM=part2`. Each entry shows one way to
answer the question. The checks accept any method that leaves the same result.

## Question 1: `site` loads `site-config`

```bash
kubectl config use-context p2-a
kubectl -n p2-web create configmap site-config --from-literal=THEME=dark --from-literal=LANG=en
kubectl -n p2-web run site --image=nginx:1.27 --dry-run=client -o yaml > site.yaml
# add envFrom under the container (configMapRef: name: site-config), then:
kubectl -n p2-web apply -f site.yaml
```

`envFrom` imports every key at once. Check with `kubectl -n p2-web exec site -- printenv THEME`.

## Question 2: `worker` gets `API_TOKEN` from `api-key`

```bash
kubectl -n p2-web create secret generic api-key --from-literal=token=s3-p2-token
kubectl -n p2-web run worker --image=busybox:1.36 --dry-run=client -o yaml -- sleep 3600 > worker.yaml
# add env: API_TOKEN with valueFrom.secretKeyRef (name: api-key, key: token), then apply
```

## Question 3: `guarded`, Guaranteed with a readiness probe

Requests must equal limits for both CPU and memory. `kubectl run` has no flags for
resources, so write the YAML, add the `resources` block and the `readinessProbe`
(`httpGet`, path `/`, port `80`), and apply it.

## Question 4: `migrate` Job

`kubectl create job` cannot set `completions`, so write the YAML with
`completions: 3`, `parallelism: 1`, `backoffLimit: 1`, and the command `sh -c 'echo migrated'`.

## Question 5: `report` CronJob and `report-now`

```bash
kubectl -n p2-batch create cronjob report --image=busybox:1.36 --schedule="0 3 * * *" -- sh -c 'echo report'
kubectl -n p2-batch patch cronjob report -p '{"spec":{"concurrencyPolicy":"Forbid"}}'
kubectl -n p2-batch create job report-now --from=cronjob/report
kubectl -n p2-batch wait --for=condition=Complete job/report-now --timeout=180s
kubectl -n p2-batch logs job/report-now
```

## Question 6: `pipeline` with an init container

Write the `seed` init container to `/work/value` with `echo 42 > /work/value`, and
mount the `emptyDir` `work` in both containers. The init container finishes first,
so `consume` can read the value.

## Question 7: `archive` claim and `keeper`

Create the PVC without a storage class, so the default applies, and a Pod that
mounts it at `/archive`. The command writes the file: `echo ok > /archive/ok`. The
claim is `Bound` once the Pod is scheduled.

## Question 8: fix the `shop` Service

```bash
kubectl -n p2-edge patch service shop -p '{"spec":{"selector":{"app":"shop"}}}'
kubectl -n p2-edge get endpointslices -l kubernetes.io/service-name=shop
```

The selector was `app=shp`. Changing the value of `app` in place fixes it.

## Question 9: the `shop` Ingress

```bash
kubectl -n p2-edge create ingress shop --class=nginx --rule='shop.p2.example.test/app*=shop:80'
```

The trailing `*` gives the `Prefix` path type. Without it the path type would be `Exact`.

## Question 10: the `web` Helm release

```bash
helm -n p2-release install web /tmp/kbook/part2/10/chart --set replicaCount=2
helm -n p2-release status web
```

## Question 11: roll `api` back

```bash
kubectl -n p2-release rollout history deployment/api
kubectl -n p2-release rollout undo deployment/api --to-revision=1
kubectl -n p2-release rollout status deployment/api
```

Revision 1 runs `nginx:1.26`. The rollback becomes a new revision.

## Question 12: the crash message

```bash
crash_log="$(kubectl -n p2-ops logs crash)"
grep -m1 fatal <<<"$crash_log" > /tmp/kbook/part2/12/message.txt
```

`logs --previous` can be unavailable on the kind node. The current run prints the
same line, so the current logs are enough.

## Question 13: the PodDisruptionBudget

```bash
kubectl api-resources --api-group=policy
```

The served version is `policy/v1`, so write the manifest with `apiVersion: policy/v1`,
`minAvailable: 1`, and the selector `app: api`, in Namespace `p2-ops`.

## Question 14: relabel the `tool` Pods

```bash
kubectl -n p2-ops label pod tool-1 tool-2 tool-3 stage=new --overwrite
```

Do not touch `keep`. Its label stays `stage=keep`.
