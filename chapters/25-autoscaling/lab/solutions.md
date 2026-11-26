# Chapter 25 lab: solutions

Try each task before reading its solution. The commands below pass `-n ch25-scale`
explicitly, because the lab does not change your default namespace.

## Task 1: the HPA for `api`

```bash
cat <<'YAML' | kubectl -n ch25-scale apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 1
  maxReplicas: 4
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
YAML
```

`autoscaling/v2` is the version with the `metrics` list. The CPU target is a
utilization percentage of the Pod's request, so the Deployment needs its request
(setup gives it `100m`).

## Task 2: wait for the scale-up

```bash
kubectl -n ch25-scale get deployment api -w
```

Stop the watch once `READY` shows at least 2. The Deployment's busy loop keeps
utilization far above 50%, so the HPA raises the count, up to its maximum of 4.

## Task 3: the metric the HPA reads

```bash
kubectl -n ch25-scale get hpa api -o jsonpath='{.status.currentMetrics[0].resource.name}' > /tmp/ch25-metric.txt
```

The status lists the metric the controller observed, `cpu`.

## Task 4: a scale-down window

```bash
kubectl -n ch25-scale patch hpa api --type=merge -p '{"spec":{"behavior":{"scaleDown":{"stabilizationWindowSeconds":60}}}}'
```

`behavior` sits in the HPA's spec, and `scaleDown` holds the window.

## Task 5: the served API version

```bash
kubectl api-resources --api-group=autoscaling --no-headers | awk '$NF=="HorizontalPodAutoscaler"{print $3}' > /tmp/ch25-hpa-api.txt
```

The output names `autoscaling/v2`, the version this cluster serves.

## Task 6: a VPA that only recommends

There is no `kubectl create` command for a VPA, so write it as YAML:

```bash
kubectl -n ch25-scale apply -f - <<'EOF'
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: worker
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: worker
  updatePolicy:
    updateMode: "Off"
EOF
kubectl -n ch25-scale get vpa worker
```

Quote `"Off"`: unquoted, YAML reads `Off` as the boolean `false`, and the API server
rejects it. Repeat `kubectl get vpa worker` until the `CPU` and `MEM` columns show
values; the recommender needs a minute or two of metrics before it publishes them.
`kubectl describe vpa worker` shows the full recommendation: a `Target`, and the
`Lower Bound` and `Upper Bound` around it.

## Task 7: the busiest Pod

```bash
kubectl -n ch25-scale top pods -l tier=batch --sort-by=cpu
```

```text
NAME      CPU(cores)   MEMORY(bytes)
batch-2   201m         0Mi
batch-3   51m          0Mi
batch-1   0m           0Mi
```

`--sort-by=cpu` puts the busiest Pod first, and `-l` limits the list to the label.
Write only the name, without the header or the numbers:

```bash
kubectl -n ch25-scale top pods -l tier=batch --sort-by=cpu --no-headers | head -1 | awk '{print $1}' > /tmp/ch25-top-pod.txt
```

If `kubectl top` lists fewer Pods than there are, or says metrics are not
available for a Pod, wait a minute: metrics-server reports a Pod only after it has
scraped it. The same command works for nodes
(`kubectl top nodes --sort-by=memory`), and `--containers` splits a Pod's use per container.

## Why these checks accept any correct method

The checks read the HPA's stored spec, the Deployment's ready replicas, the metric
name in the HPA's status, the served API version, and the VPA's spec and status,
plus the files you write. You can create the HPA with YAML or `kubectl autoscale`,
and the checks do not care which.
