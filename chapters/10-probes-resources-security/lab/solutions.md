# Chapter 10 lab: solutions

Try each task before reading its solution. The commands below assume `kubectl`
defaults to `ch10-health` (run `make use-namespace CH=10` once). Otherwise, add
`-n ch10-health` to every command.

## Task 1: `gate`, a readiness probe that waits for a file

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gate
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      readinessProbe:
        exec:
          command: ["cat", "/tmp/ready"]
        periodSeconds: 2
YAML
kubectl wait --for=jsonpath='{.status.phase}'=Running pod/gate --timeout=120s
kubectl exec gate -- touch /tmp/ready
kubectl wait --for=condition=Ready pod/gate --timeout=120s
```

Until the file exists, the probe fails and the Pod stays `0/1`. The file must be
created after the container has started, because `exec` needs a running
container. The probe is re-run every 2 seconds, so the Pod becomes Ready soon
after the touch.

## Task 2: `healthy`, a liveness probe on HTTP

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: healthy
spec:
  containers:
    - name: app
      image: nginx:1.27
      livenessProbe:
        httpGet:
          path: /
          port: 80
        initialDelaySeconds: 5
        periodSeconds: 10
YAML
kubectl wait --for=condition=Ready pod/healthy --timeout=120s
```

The fields are `httpGet.path`, `httpGet.port`, `initialDelaySeconds`, and
`periodSeconds`. Nginx answers `/` with 200, so the probe passes.

## Task 3: `sized`, a Burstable Pod

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: sized
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      resources:
        requests:
          cpu: 100m
          memory: 64Mi
        limits:
          cpu: 200m
          memory: 128Mi
YAML
kubectl get pod sized -o jsonpath='{.status.qosClass}{"\n"}'
```

The requests and limits differ, so the class is `Burstable`.

## Task 4: `pinned`, a Guaranteed Pod

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pinned
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      resources:
        requests:
          cpu: 250m
          memory: 128Mi
        limits:
          cpu: 250m
          memory: 128Mi
YAML
kubectl get pod pinned -o jsonpath='{.status.qosClass}{"\n"}'
```

Requests equal limits for both CPU and memory, so the class is `Guaranteed`.

## Task 5: `hardened`, a non-root Pod without capabilities

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: hardened
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
YAML
kubectl exec hardened -- id -u
kubectl exec hardened -- grep CapEff /proc/1/status
```

`runAsUser` and `runAsNonRoot` are Pod-level; `allowPrivilegeEscalation` and
`capabilities` are container-level. `CapEff` is all zeros when every
capability is dropped.

## Task 6: limit the Namespace

Create the LimitRange first. Admission fills in its defaults when a Pod is
created, so a Pod created before it gets none, and once the quota exists, a Pod
without resources is rejected.

```bash
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: LimitRange
metadata:
  name: defaults
spec:
  limits:
    - type: Container
      defaultRequest:
        cpu: 100m
        memory: 64Mi
      default:
        cpu: 200m
        memory: 128Mi
YAML
kubectl create quota compute --hard=pods=10,requests.cpu=2,requests.memory=2Gi,limits.cpu=4,limits.memory=4Gi
kubectl run plain --image=nginx:1.27
kubectl get pod plain -o jsonpath='{.spec.containers[0].resources}'; echo
kubectl describe quota compute
```

`plain` shows `"requests":{"cpu":"100m","memory":"64Mi"}` and the matching
limits, although its manifest named none. `describe quota` shows the Pods and
resources already counted against each cap.

## Why these checks accept any correct method

Each check reads the outcome: the Pod's readiness and QoS class, the spec fields
the task names, and the values a running container reports (its user ID, its
capability set, and the probe file). You can create the Pods with YAML or with a
generated manifest. The checks do not care.
