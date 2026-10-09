# Part I simulator: solutions

Score yourself with `make mock-score EXAM=part1` before reading on. Every
command passes `-n` and assumes you already ran the question's "Use context"
command.

## Question 1 | Contexts

```bash
kubectl config get-contexts -o name > /tmp/kbook/part1/1/contexts
kubectl config view -o jsonpath='{.contexts[?(@.name=="p1-b")].context.namespace}' > /tmp/kbook/part1/1/namespace
```

`kubectl config get-contexts` without `-o name` prints a table; the `*` marks
the current context. The default namespace of a context is part of the
kubeconfig, not the cluster: `p1-b` defaults to `p1-europa`, so a command run
there without `-n` lands in `p1-europa`, not `default`.

## Question 2 | Pod with a named container

`kubectl run` names the container after the Pod and has no flag to change
that. Generate, edit, apply:

```bash
kubectl -n p1-io run courier --image=nginx:1.27 --labels=app=courier,tier=edge \
  --port=80 --dry-run=client -o yaml > courier.yaml
vim courier.yaml     # under containers:, change "name: courier" to "name: courier-container"
kubectl apply -f courier.yaml
```

## Question 3 | Fix a crashing Pod

```bash
kubectl -n p1-europa describe pod ledger      # Events: exec: "sleeep": executable file not found
kubectl -n p1-europa get pod ledger -o yaml > ledger.yaml
vim ledger.yaml                                # fix the command: sleep
kubectl replace --force -f ledger.yaml
```

A container's `command` is immutable, so `kubectl edit` is rejected; it saves
your change to a temporary file, which you can then use with
`kubectl replace --force -f`. Exporting the live object keeps the image,
labels, and annotations for free. Note the Pod's phase stays `Running` while
the container crash-loops: check `READY` and `RESTARTS`, not just `STATUS`.

## Question 4 | Logs of a container that crashed

```bash
kubectl -n p1-titan get pod beacon            # RESTARTS shows 1
kubectl -n p1-titan get pod beacon -o jsonpath='{range .status.containerStatuses[*]}{.name} {.restartCount}{"\n"}{end}'
kubectl -n p1-titan logs beacon -c agent      # only "agent restarted, nothing to report"
kubectl -n p1-titan logs beacon -c agent --previous | grep token
kubectl -n p1-titan logs beacon -c agent --previous | grep -m1 '^token=' | cut -d= -f2 > /tmp/kbook/part1/4/token
echo agent > /tmp/kbook/part1/4/container
```

Without `-c`, `kubectl logs` on a multi-container Pod picks the default
container (or refuses). Without `--previous`, you read the *current* instance,
which has nothing to say.

## Question 5 | Requests without a CPU limit

```bash
kubectl -n p1-titan run cruncher --image=busybox:1.36 --dry-run=client -o yaml \
  --command -- sleep 3600 > cruncher.yaml
vim cruncher.yaml
kubectl apply -f cruncher.yaml
```

```yaml
    resources:
      requests:
        cpu: 50m
        memory: 32Mi
      limits:
        memory: 64Mi
```

Leaving out `limits.cpu` is deliberate and common: the container may use spare
CPU, but its memory is capped.

## Question 6 | Exit codes

```bash
kubectl -n p1-io run migrate --image=busybox:1.36 --restart=Never -- sh -c 'echo migration finished; exit 4'
kubectl -n p1-io get pod importer -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' > /tmp/kbook/part1/6/exit-code
```

A non-zero exit with `restartPolicy: Never` leaves the Pod in phase `Failed`.
`kubectl describe pod importer` also shows the exit code, under
`State: Terminated`.

## Question 7 | Labels and annotations by selector

```bash
kubectl -n p1-callisto label pods -l 'tier in (db,cache)' protected=true
kubectl -n p1-callisto annotate pods -l env=prod audit=q4-2026
kubectl -n p1-callisto get pods -L tier,env,protected       # check
```

## Question 8 | Change and remove labels

```bash
kubectl -n p1-callisto label pods -l stage=beta stage=ga --overwrite
kubectl -n p1-callisto label pods -l temp temp-
```

`-l temp` selects Pods that have the key at all, whatever its value. A trailing
`-` removes a label. Without `--overwrite`, changing an existing value fails.

## Question 9 | Find information fast

```bash
kubectl -n p1-callisto get pods \
  -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[*].image}{"\n"}{end}' \
  | grep 'nginx:1.26' | cut -d' ' -f1 > /tmp/kbook/part1/9/pods
kubectl -n p1-callisto get pods -o jsonpath='{.items[*].spec.containers[*].name}' | wc -w > /tmp/kbook/part1/9/containers
```

Two of the Pods have a second container. Looking only at
`.spec.containers[0]` misses one of the `nginx:1.26` Pods, and counting Pods
gives the wrong total.

## Question 10 | Generate, edit, create

```bash
kubectl run gateway --image=nginx:1.27 --labels=app=gateway --env=MODE=edge \
  --dry-run=client -o yaml > /tmp/kbook/part1/10/gateway.yaml
vim /tmp/kbook/part1/10/gateway.yaml
kubectl -n p1-io apply -f /tmp/kbook/part1/10/gateway.yaml
```

Add the second item to the `containers` list:

```yaml
  containers:
  - env:
    - name: MODE
      value: edge
    image: nginx:1.27
    name: gateway
    resources: {}
  - name: helper
    image: busybox:1.36
    command: ["sleep", "3600"]
```

Without a long-running command, `busybox` exits at once and the `helper`
container crash-loops.

## Question 11 | Config objects

```bash
kubectl -n p1-europa create configmap ledger-config --from-literal=currency=EUR --from-literal=rounding=half-even
kubectl -n p1-europa create secret generic ledger-db --from-literal=user=ledger --from-literal=password=l3dg3r-pw
kubectl -n p1-europa create serviceaccount ledger-sa
kubectl -n p1-europa expose pod ledger --name=ledger-svc --port=8080 --target-port=80
```

`expose` copies the Pod's labels into the Service's selector. If you recreated
`ledger` in Question 3 with its labels intact, the Service still finds it.

## Question 12 | Ask the API

```bash
kubectl api-resources | grep -i cronjob        # batch/v1
echo batch/v1 > /tmp/kbook/part1/12/cronjob-api
kubectl explain pod.spec.containers.securityContext.runAsNonRoot   # <boolean>
echo boolean > /tmp/kbook/part1/12/run-as-non-root
kubectl api-resources --namespaced=false | grep -w Namespace
echo no > /tmp/kbook/part1/12/namespaced
```

## Question 13 | Permissions

```bash
SA=system:serviceaccount:p1-titan:auditor
kubectl auth can-i list pods    -n p1-titan --as=$SA   # yes (view role)
kubectl auth can-i get secrets  -n p1-titan --as=$SA   # no  (view leaves out Secrets)
kubectl auth can-i create pods  -n p1-io    --as=$SA   # yes (Role pod-writer)
kubectl auth can-i list pods    -n p1-io    --as=$SA   # no  (pod-writer: create, delete only)
printf 'yes\nno\nyes\nno\n' > /tmp/kbook/part1/13/answers
```

## Question 14 | How the control plane runs

```bash
kubectl -n kube-system get pod -l component=kube-apiserver \
  -o jsonpath='{.items[0].spec.containers[0].image}' > /tmp/kbook/part1/14/apiserver-image
kubectl -n kube-system get pod -l k8s-app=kube-proxy -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}'
echo DaemonSet > /tmp/kbook/part1/14/proxy-owner
kubectl -n kube-system get pod -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}'  # ReplicaSet
kubectl -n kube-system get replicaset -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}'  # Deployment
echo Deployment > /tmp/kbook/part1/14/dns-owner
```

kube-apiserver is a static Pod (its owner is the Node, Chapter 02). kube-proxy
must run once on every node, so a DaemonSet manages it. CoreDNS is an ordinary
Deployment, which manages a ReplicaSet, which manages the Pods.
