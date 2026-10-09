# Chapter 03 lab: solutions

Try each task before reading its solution. Every command passes `-n` explicitly,
so it works whatever your default namespace is. If you ran
`make use-namespace CH=3 PART=<part>` you can leave `-n` out.

Answer files are written to `/tmp`. Run `make verify CH=3 PART=<part>` after each part.

## Part a

```bash
kubectl -n ch03-kubectl get pods --show-labels      # look first
```

**A1.** Comma means AND in a selector. `-o name` prints `pod/NAME`; the check accepts that, or bare names:

```bash
kubectl -n ch03-kubectl get pods -l env=prod,tier=web -o name > /tmp/ch03-a1.txt
```

**A2.** `custom-columns` is the shortest way:

```bash
kubectl -n ch03-kubectl get pods \
  -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image \
  --no-headers > /tmp/ch03-a2.txt
```

A JSONPath equivalent:

```bash
kubectl -n ch03-kubectl get pods \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}' > /tmp/ch03-a2.txt
```

**A3.** `!=` and `notin` both include Pods that have no `env` label (here, `batch-1`):

```bash
kubectl -n ch03-kubectl get pods -l 'env!=prod' -o name > /tmp/ch03-a3.txt
# same result:  -l 'env notin (prod)'
```

**A4.** `annotate` accepts a selector:

```bash
kubectl -n ch03-kubectl annotate pods -l tier=db reviewed=true
```

**A5.** Generate, save, then create from the file:

```bash
kubectl -n ch03-kubectl run api --image=nginx:1.27 --labels=app=api \
  --dry-run=client -o yaml > /tmp/ch03-api.yaml
kubectl -n ch03-kubectl apply -f /tmp/ch03-api.yaml
```

**A6.**

```bash
kubectl explain pod.spec.terminationGracePeriodSeconds   # the header shows <integer>
echo integer > /tmp/ch03-a6.txt
```

**A7 (optional).**

```bash
# jq
kubectl -n ch03-kubectl get pods -o json \
  | jq -r '[.items[].spec.containers[].image] | unique | .[]' > /tmp/ch03-a7.txt
# or yq
kubectl -n ch03-kubectl get pods -o yaml \
  | yq '[.items[].spec.containers[].image] | unique | .[]' > /tmp/ch03-a7.txt
# or neither
kubectl -n ch03-kubectl get pods -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' | sort -u > /tmp/ch03-a7.txt
```

## Part b1

```bash
kubectl config view          # note the cluster and user names of your current context
kubectl config current-context
```

**B1.1, B1.2.** Use the cluster and user names you saw (for the lab cluster both are usually `kind-kbook`):

```bash
kubectl config set-context ch03-a --cluster=kind-kbook --user=kind-kbook --namespace=ch03-b1-a
kubectl config set-context ch03-b --cluster=kind-kbook --user=kind-kbook --namespace=ch03-b1-b
```

**B1.3, B1.4.** `--context` reads through a context without switching to it:

```bash
kubectl --context ch03-a get configmap where -o jsonpath='{.data.value}' > /tmp/ch03-b1-a.txt
kubectl --context ch03-b get configmap where -o jsonpath='{.data.value}' > /tmp/ch03-b1-b.txt
```

You can switch instead (`kubectl config use-context ch03-a`, then `get configmap where ...`); both approaches pass. Switch back with `kubectl config use-context kind-kbook`, or run `make teardown CH=3 PART=b1` when you finish.

## Part b2p

```bash
kubectl -n ch03-b2p get pods
```

**P1.**

```bash
kubectl -n ch03-b2p run probe --image=busybox:1.36 --labels=role=probe --command -- sleep 3600
```

**P2.** `--restart=Never` and the command after `--`:

```bash
kubectl -n ch03-b2p run hello --image=busybox:1.36 --restart=Never -- echo "hello from ch03"
```

**P3.**

```bash
kubectl -n ch03-b2p label pod web tier=front
kubectl -n ch03-b2p annotate pod web contact=ops
```

**P4.** Find the container's name, then change its image in place:

```bash
kubectl -n ch03-b2p get pod web -o jsonpath='{.spec.containers[*].name}'     # web
kubectl -n ch03-b2p set image pod/web web=nginx:1.27
```

Deleting and recreating the Pod would also give it the new image, but it would be a *different* Pod with a different unique ID, which the check rejects.

**P5.**

```bash
kubectl -n ch03-b2p run envpod --image=busybox:1.36 --env=APP_MODE=test --command -- sleep 3600
```

**P6.**

```bash
kubectl -n ch03-b2p delete pod junk --now
```

## Part b2

**C1 to C5.**

```bash
kubectl -n ch03-b2 create configmap app-config --from-literal=APP_MODE=prod --from-literal=LOG_LEVEL=info
kubectl -n ch03-b2 create secret generic db-pass --from-literal=password=hunter2
kubectl -n ch03-b2 create serviceaccount robot
kubectl -n ch03-b2 run hello --image=busybox:1.36 --restart=Never -- echo "hello from ch03"
kubectl -n ch03-b2 expose pod web --port=80
```

`expose` builds a Service whose selector is the Pod's labels (`app=web`); the target port defaults to the same number as `--port`.

## Part b3

```bash
SA=system:serviceaccount:ch03-b3:viewer
kubectl auth can-i delete pods  -n ch03-b3     --as=$SA   # no
kubectl auth can-i list secrets -n ch03-b3     --as=$SA   # no
kubectl auth can-i get pods     -n ch03-b3     --as=$SA   # yes
kubectl auth can-i list pods    -n kube-system --as=$SA   # no
```

The built-in `view` role allows reading most objects in a namespace but **not Secrets**, and the binding applies only to `ch03-b3`. The expected answers are therefore `no`, `no`, `yes`, `no`. Remember `can-i` exits with status 1 for `no`, so write the file without letting that stop your shell:

```bash
{ kubectl auth can-i delete pods  -n ch03-b3     --as=$SA || true
  kubectl auth can-i list secrets -n ch03-b3     --as=$SA || true
  kubectl auth can-i get pods     -n ch03-b3     --as=$SA || true
  kubectl auth can-i list pods    -n kube-system --as=$SA || true
} > /tmp/ch03-b3.txt
```

## Part final

```bash
# 1
kubectl -n ch03-f1 run sleeper --image=busybox:1.36 --labels=team=blue --command -- sleep 3600
# 2
kubectl -n ch03-f1 get pods -l team=red -o name > /tmp/ch03-final-red.txt
# 3  (--overwrite is required to change an existing value)
kubectl -n ch03-f2 label pods -l stage=old stage=new --overwrite
# 4  (look up the container name first)
kubectl -n ch03-f2 get pod x1 -o jsonpath='{.spec.containers[*].name}'     # web
kubectl -n ch03-f2 set image pod/x1 web=nginx:1.27
# 5
kubectl -n ch03-f2 run gen --image=busybox:1.36 --env=FOO=bar \
  --dry-run=client -o yaml --command -- sleep 3600 > /tmp/ch03-final-gen.yaml
kubectl -n ch03-f2 apply -f /tmp/ch03-final-gen.yaml
# 6
kubectl -n ch03-f1 get pods \
  -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image --no-headers \
  | awk '$2=="nginx:1.26"{print $1}' > /tmp/ch03-final-img.txt
```

In step 3 the selector `-l stage=old` is evaluated once, before any change, so relabelling the matching Pods does not affect which Pods are chosen.
