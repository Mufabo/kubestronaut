# kubectl cheat sheet

One page of the commands from Chapter 03. `k` is the alias for `kubectl`
(`envs/shell/kubectl-exam.sh`), `$do` is `--dry-run=client -o yaml`, and
`$now` is `--force --grace-period 0`.

## Contexts and namespaces

| Task | Command |
|---|---|
| List contexts / show current | `k config get-contexts` / `k config current-context` |
| Switch context | `k config use-context NAME` |
| Default namespace of current context | `k config set-context --current --namespace=NS` (or `kn NS`) |
| Create a context | `k config set-context NAME --cluster=C --user=U --namespace=NS` |
| Delete / rename | `k config delete-context NAME` / `k config rename-context OLD NEW` |
| One-off context or namespace | `k --context NAME ...` / `k -n NS ...` |
| Show current context only | `k config view --minify` |

## Getting information

| Task | Command |
|---|---|
| Wide / YAML / JSON / names | `-o wide`, `-o yaml`, `-o json`, `-o name` |
| All namespaces | `-A` |
| Watch | `-w` |
| Labels as text / as columns | `--show-labels` / `-L env,tier` |
| No header row | `--no-headers` |
| Sort | `--sort-by=.metadata.creationTimestamp` |
| Label selector | `-l env=prod,tier=web`, `-l env!=prod`, `-l 'env in (a,b)'`, `-l 'env notin (a)'`, `-l env`, `-l '!env'` |
| Field selector | `--field-selector status.phase=Running`, `--field-selector spec.nodeName=NODE` |
| One field | `-o jsonpath='{.status.podIP}'` |
| One value per line | `-o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'` |
| Filter inside a list | `{.spec.containers[0].env[?(@.name=="X")].value}` |
| Custom table | `-o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image` |
| Events by time | `k get events --sort-by=.lastTimestamp` |
| Several kinds at once | `k get pods,svc,cm,secret,sa` (`get all` is **not** everything) |

## Discovering the API

| Task | Command |
|---|---|
| All resource types | `k api-resources` |
| Cluster-scoped only | `k api-resources --namespaced=false` |
| One group, with verbs | `k api-resources --api-group=apps -o wide` |
| Field documentation | `k explain pod.spec.containers` (`--recursive` for the tree) |
| Raw API call | `k get --raw /version` |

## Creating

| Task | Command |
|---|---|
| Pod | `k run NAME --image=IMG [--port=P] [--labels=a=b] [--env=K=V] [--restart=Never] [--command] -- ARGS` |
| ConfigMap | `k create configmap NAME --from-literal=K=V` |
| Secret | `k create secret generic NAME --from-literal=K=V` |
| ServiceAccount / Namespace | `k create serviceaccount NAME` / `k create namespace NAME` |
| Service for a Pod | `k expose pod NAME --port=80` |
| Print instead of create | add `$do` (`--dry-run=client -o yaml`) |
| Validate on the server, store nothing | `--dry-run=server` |

## Changing

| Task | Command |
|---|---|
| Create or update from a file | `k apply -f FILE` |
| Create only (error if it exists) | `k create -f FILE` |
| Delete and recreate | `k replace --force -f FILE` |
| Preview an apply | `k diff -f FILE` (exit 1 means differences) |
| Edit live | `k edit pod NAME` |
| Patch | `k patch pod NAME -p '{"metadata":{"labels":{"a":"b"}}}'` (`--type=merge`, `--type=json`) |
| Label / remove label | `k label pod NAME a=b [--overwrite]` / `k label pod NAME a-` |
| Annotate | `k annotate pod NAME k=v` |
| Many objects | add `-l SELECTOR` instead of a name |
| Change a Pod's image | `k set image pod/NAME CONTAINER=IMG` |
| Delete | `k delete pod NAME [--now] [--ignore-not-found]`, `k delete pods -l a=b` |
| Delete at once (labs only) | `k delete pod NAME $now` |
| Wait | `k wait --for=condition=Ready pod/NAME --timeout=60s`, `--for=delete` |

## Deployments and rollouts (Chapter 05)

| Task | Command |
|---|---|
| Create | `k create deployment NAME --image=IMG --replicas=N [--port=P]` (container is named after the image) |
| Scale | `k scale deployment NAME --replicas=N` |
| Container names | `k get deploy NAME -o jsonpath='{.spec.template.spec.containers[*].name}'` |
| New image | `k set image deployment/NAME CONTAINER=IMG` |
| Record why | `k annotate deployment NAME kubernetes.io/change-cause="..." --overwrite` |
| Follow a rollout | `k rollout status deployment/NAME [--timeout=60s]` |
| History / one revision | `k rollout history deployment/NAME [--revision=N]` |
| Roll back | `k rollout undo deployment/NAME [--to-revision=N]` |
| Batch several changes | `k rollout pause deployment/NAME` ... `k rollout resume deployment/NAME` |
| ReplicaSets of a Deployment | `k get rs -l app=NAME` (old revisions show 0 desired) |

## Permissions

| Task | Command |
|---|---|
| Can I? | `k auth can-i create pods -n NS` |
| Can they? | `k auth can-i list secrets -n NS --as=system:serviceaccount:NS:SA` |
| Everything I can do | `k auth can-i --list -n NS` |

`can-i` prints `yes` or `no`; the exit status is 0 for yes and **1 for no**.

## jq and yq (mikefarah v4)

| Task | Command |
|---|---|
| Names | `k get pods -o json \| jq -r '.items[].metadata.name'` |
| Filter | `jq -r '.items[] \| select(.metadata.labels.env=="prod") \| .metadata.name'` |
| Distinct values | `jq -r '[.items[].spec.containers[].image] \| unique \| .[]'` |
| Read YAML | `yq '.spec.containers[0].image' FILE` |
| Edit YAML in place | `yq -i '.spec.containers[0].image = "nginx:1.28"' FILE` |
| Append to a list | `yq -i '.spec.containers[0].env += [{"name":"A","value":"b"}]' FILE` |
| Drop server fields | `yq 'del(.status) \| del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp)' FILE` |
| JSON to YAML | `yq -p=json -o=yaml '.' FILE.json` |

## vim for YAML

`:set expandtab tabstop=2 shiftwidth=2` first. `i` insert, `Esc` leave insert,
`:wq` save and quit, `:q!` discard, `dd` delete line, `yy` copy line, `p` paste,
`u` undo, `/text` search, `>>` indent, `:set paste` before pasting a block.
