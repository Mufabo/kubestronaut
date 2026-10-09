# Chapter 03: Lab setup and `kubectl` fluency

> **Exams:** KCNA · CKAD · CKA (and every later hands-on chapter and CKS)
> **Difficulty:** Beginner to intermediate
> **Time:** ~90 min reading, ~60 min lab
> **Lab tier:** 1 (kind)
> **Prerequisites:** Chapters 01 and 02

## Learning objectives

After this chapter you can:

1. Install and verify Docker, kind, `kubectl`, and `make`, create the lab cluster, and diagnose a cluster that will not start
2. Read and edit a kubeconfig: create, switch, and delete contexts, set a default namespace, and use several kubeconfig files at once
3. Extract exactly the data you need with `-o` formats, selectors, JSONPath, and `custom-columns`, and post-process output with `jq` and `yq`
4. Discover the API offline with `api-resources`, `explain`, and `get --raw`
5. Create objects imperatively and generate manifests with `--dry-run=client -o yaml`
6. Choose correctly between `create`, `apply`, `replace`, `edit`, and `patch`, and preview a change with `diff`
7. Modify live Pods with `label`, `annotate`, `set image`, and `delete`, wait for readiness with `wait`, and know which commands (`scale`, `set env`, `set resources`, `rollout`) need a controller and are practised from Chapter 05
8. Check permissions with `kubectl auth can-i`, including impersonation with `--as`
9. Set up a fast terminal: alias, completion, exam variables, `vim`, and an optional `tmux`
10. Work through a timed set of tasks and read your own elapsed time

Chapter 02 gave you a ten-line `kubectl` primer and the structure of a kubeconfig. This chapter assumes that and goes deeper.

> **Pods in one paragraph.** The labs in this chapter use only Pods, so you do not need the controllers yet. You saw how a Pod is created in Chapter 02, and Chapter 04 covers Pods in depth. For now: a Pod runs one or more containers, has a name and labels, and reports a phase (`Running` while it runs, `Succeeded` once a run-to-completion Pod has finished). If a Pod dies, nothing brings that same Pod back.

## 1. Setting up your lab

You need four tools: a container runtime (Docker), **kind** (Kubernetes in Docker), **kubectl**, and **make**. `jq` and `yq` are used in section 4.

| Platform | Notes |
|---|---|
| Linux | Docker Engine, or any runtime kind supports |
| macOS | Docker Desktop (or an alternative runtime that kind supports) |
| Windows | Use **WSL2**. Native PowerShell is not supported by this book. Install Docker Desktop with WSL integration turned on, or Docker Engine inside your WSL2 distribution, and keep the repository in the Linux filesystem (`~/`), not under `/mnt/c`, or everything is slow |

The versions below are the ones pinned in `versions.env`. Re-check upstream releases when you start a new edition of the book.

```bash
# Docker (Linux)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"        # log out and back in afterwards

# kind
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.31.0/kind-linux-amd64
chmod +x kind && sudo mv kind /usr/local/bin/kind

# kubectl (match the cluster version; use arm64 instead of amd64 on ARM)
curl -LO https://dl.k8s.io/release/v1.35.0/bin/linux/amd64/kubectl
chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl

# make
sudo apt-get update && sudo apt-get install -y make

# jq and yq (section 4). yq must be mikefarah/yq v4, the Go program.
curl -Lo jq https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-amd64
curl -Lo yq https://github.com/mikefarah/yq/releases/download/v4.54.1/yq_linux_amd64
chmod +x jq yq && sudo mv jq yq /usr/local/bin/
```

On macOS: `brew install --cask docker && brew install kind kubectl make jq yq`. Check everything:

```bash
docker version && kind version && kubectl version --client && make --version
jq --version && yq --version
```

`yq --version` must mention `mikefarah`. A different program is also called `yq` (a Python wrapper around `jq`) and it uses different syntax.

### Create the lab cluster

From the repository root:

```bash
make cluster
kubectl get nodes
```

`make cluster` creates a kind cluster named `kbook` (one control plane node and two workers), using the Kubernetes version pinned in `versions.env`. It also adds a small marker to the cluster. Every lab script checks, before it changes anything, that your current context is **exactly** `kind-kbook` **and** that the cluster carries that marker. That is what stops a lab from ever deleting a namespace on a cluster you care about. If you move to a different cluster on purpose, the safety override exists (`LAB_ALLOW_ANY_CONTEXT=1`), but you are on your own then.

You should see three nodes, all `Ready`:

```text
NAME                  STATUS   ROLES           AGE   VERSION
kbook-control-plane   Ready    control-plane   2m    v1.35.0
kbook-worker          Ready    <none>          2m    v1.35.0
kbook-worker2         Ready    <none>          2m    v1.35.0
```

*(Example output; ages and versions will differ.)*

### When the cluster will not start

| Symptom | Likely cause | Fix |
|---|---|---|
| `Cannot connect to the Docker daemon` | Docker is not running, or your user is not in the `docker` group | Start Docker; log out and back in after `usermod` |
| `kind create cluster` hangs or fails pulling the node image | No network, or a proxy | Check connectivity; `docker pull kindest/node:v1.35.0` by hand shows the real error |
| Nodes stay `NotReady` | Not enough memory for Docker | Give Docker 4 GB or more; delete the cluster and retry |
| `make cluster` says the cluster runs another version | You changed `versions.env` | `make cluster-recreate` |
| Context `kind-kbook` missing | Cluster deleted, or kubeconfig replaced | `make cluster` |
| WSL2: `docker: command not found` | Docker Desktop's WSL integration is off for your distribution | Turn it on in Docker Desktop settings |

To start over: `make cluster-recreate`. To remove the cluster entirely: `make cluster-delete`.

**Hardware.** Tier 1 labs (this chapter) need about 4 GB of RAM free for Docker. The multi-VM Tier 2 environment used later in the book needs 8 to 16 GB; the book offers a hosted option for readers who do not have that.

## 2. kubeconfig and contexts

Chapter 02 introduced the structure: a kubeconfig lists **clusters**, **users** (credentials), and **contexts** (a name for a cluster + user + optional default namespace), plus a **current-context**. Here is what you do with it.

```bash
kubectl config get-contexts                 # list them; * marks the current one
kubectl config current-context
kubectl config use-context kind-kbook       # switch
kubectl config view --minify                # only the current context
kubectl config view                         # everything (credentials shown as DATA/REDACTED)
```

Create, change, rename, and delete contexts:

```bash
kubectl config set-context dev --cluster=kind-kbook --user=kind-kbook --namespace=dev
kubectl config set-context --current --namespace=dev     # change the CURRENT context's namespace
kubectl config rename-context dev development
kubectl config delete-context development
```

`set-context` on an existing name only changes the fields you give it. `--current` means "the context I am using right now".

**One-off overrides** do not touch the file at all:

```bash
kubectl --context kind-kbook -n kube-system get pods
kubectl --kubeconfig ~/other-config get nodes
```

**Several files.** `KUBECONFIG` can hold a colon-separated list; `kubectl` merges them in order. `kubectl config view --flatten` prints the merged result.

```bash
export KUBECONFIG=~/.kube/config:~/work.kubeconfig
```

Practical rules:

- Always know which context you are in before you run anything that deletes. The lab tooling checks for you; production does not.
- Prefer `-n NAMESPACE` on commands over changing your default namespace. A command with `-n` means the same thing wherever you run it.
- The lab does **not** change your default namespace. If you want that convenience, opt in explicitly with `make use-namespace CH=3` (it saves what you had, and `make teardown CH=3` puts it back), or use the `kn` helper from section 9.

> **Exam tip:** Exam tasks typically tell you which cluster or context to use. Run exactly the context command the task gives, every time. Working in the wrong cluster is the cheapest way to lose a task you solved correctly.

## 3. Getting exactly the data you need

### Output formats

```bash
kubectl get pods                       # default table
kubectl get pods -o wide               # more columns (node, IP)
kubectl get pods -o name               # pod/web-prod-1, one per line
kubectl get pod web-prod-1 -o yaml     # the full stored object
kubectl get pod web-prod-1 -o json
kubectl get pods --show-labels         # a LABELS column
kubectl get pods -L env,tier           # one column per label
kubectl get pods --no-headers          # drop the header row (handy in scripts)
kubectl get pods -A                    # all namespaces
kubectl get pods -w                    # watch for changes (Ctrl-C to stop)
```

```text
NAME          READY   STATUS    RESTARTS   AGE   ENV    TIER
web-prod-1    1/1     Running   0          4m    prod   web
web-dev-1     1/1     Running   0          4m    dev    web
batch-1       1/1     Running   0          4m           batch
```

*(Example output of `kubectl get pods -L env,tier`.)*

Sort with a JSONPath-style field: `kubectl get pods --sort-by=.metadata.creationTimestamp`.

### Selecting objects

**Label selectors** (`-l`) filter by labels:

| Selector | Meaning |
|---|---|
| `-l env=prod` | label `env` equals `prod` |
| `-l env=prod,tier=web` | both (comma means AND) |
| `-l env!=prod` | `env` is not `prod`, **including objects that have no `env` label at all** |
| `-l 'env in (prod,dev)'` | `env` is one of the values |
| `-l 'env notin (prod)'` | `env` is not in the list, also matching objects without the label |
| `-l env` | the label exists, with any value |
| `-l '!env'` | the label does not exist |

Quote selectors with spaces or parentheses so the shell leaves them alone. Many commands accept `-l`, not only `get`: `label`, `annotate`, `delete`, `logs`, and more.

**Field selectors** (`--field-selector`) filter on a few built-in fields, not on labels:

```bash
kubectl get pods --field-selector status.phase=Running
kubectl get pods --field-selector spec.nodeName=kbook-worker
kubectl get pods -A --field-selector metadata.namespace!=kube-system
```

Only a small set of fields is supported per resource, and the error message tells you when you pick an unsupported one.

### JSONPath

`-o jsonpath='...'` prints exactly the fields you choose. The template is written between single quotes, with each expression in braces:

```bash
kubectl get pod web-prod-1 -o jsonpath='{.status.podIP}'
kubectl get pods -o jsonpath='{.items[*].metadata.name}'
kubectl get pods -o jsonpath='{.items[0].spec.containers[0].image}'
```

`{.items[*].metadata.name}` prints all names on one line, separated by spaces. To print one per line, use `range`:

```bash
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

```text
web-prod-1	nginx:1.27
web-dev-1	nginx:1.27
batch-1	busybox:1.36
```

Filters select array elements. This prints the value of the environment variable `APP_MODE` of the first container:

```bash
kubectl get pod envpod -o jsonpath='{.spec.containers[0].env[?(@.name=="APP_MODE")].value}'
```

Things that trip people up:

- When you use `-o jsonpath`, a *single* object has no `.items`; a *list* (many objects) does. `kubectl get pod NAME` returns one object; `kubectl get pods` returns a list.
- Keys containing dots must be escaped: `{.metadata.labels.kubernetes\.io/name}`.
- There is no trailing newline unless you add `{"\n"}`.
- If a path matches nothing you get empty output, not an error. Check the shape with `-o yaml` first.

### custom-columns

`custom-columns` builds a table from fields, which is often quicker to write than JSONPath:

```bash
kubectl get pods -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image,NODE:.spec.nodeName
```

```text
NAME         IMAGE          NODE
web-prod-1   nginx:1.27     kbook-worker
web-dev-1    nginx:1.27     kbook-worker2
batch-1      busybox:1.36   kbook-worker
```

Add `--no-headers` to drop the first line.

### Events

Events explain *why* something happened and are the first thing to read when a Pod will not start. Sort them by time:

```bash
kubectl get events --sort-by=.lastTimestamp
kubectl describe pod NAME          # ends with that Pod's events
```

Events are kept only for a short time (about an hour by default).

> **Careful with `kubectl get all`.** Despite its name it does not list everything: ConfigMaps, Secrets, ServiceAccounts, Ingresses, PersistentVolumeClaims, and many other kinds are left out. Name the kinds you want: `kubectl get pods,svc,cm,secret,sa`.

## 4. `jq` and `yq`: when built-in output is not enough

JSONPath and `custom-columns` cover most needs. Two small tools handle the rest:

- **`jq`** processes JSON. Pipe `kubectl ... -o json` into it.
- **`yq`** processes YAML (and, with flags, JSON). Use it to read *and edit* manifests.

Use them when you need to filter by a computed condition, count, group, or edit a file in place. Use the built-in tools when they are enough, because they are always there.

> **What is available in the exam.** The Linux Foundation's exam instructions say the exam hosts have `kubectl` with the `k` alias and Bash completion, `yq`, `curl`, `wget`, and `man` pages already installed. They do not list `jq` or `tmux`. Treat `yq` as available and `jq` as a convenience you cannot count on. Everything you can do with `jq` here can also be done with JSONPath, `custom-columns`, or `yq`. Check the current instructions before your exam, because they change.

The examples below run against the sample files in `chapters/03-kubectl-fluency/testdata/` (four Pods) and are checked by `testdata/test-examples.sh`, which runs each command with the pinned `jq` and `yq` and compares the output with what you see here. In real use you would replace the file with a pipe: `kubectl get pods -o json | jq ...`.

### jq

```bash
jq -r '.items[].metadata.name' pods.json
```

```text
web-prod-1
web-prod-2
db-dev-1
batch-1
```

`-r` prints raw strings without quotes. `.items[]` iterates over the list. Name and image as tab-separated columns:

```bash
jq -r '.items[] | [.metadata.name, .spec.containers[0].image] | @tsv' pods.json
```

```text
web-prod-1	nginx:1.27
web-prod-2	nginx:1.26
db-dev-1	busybox:1.36
batch-1	busybox:1.36
```

Select by a condition, then print a field:

```bash
jq -r '.items[] | select(.metadata.labels.env == "prod") | .metadata.name' pods.json
```

```text
web-prod-1
web-prod-2
```

All distinct images in use:

```bash
jq -r '[.items[].spec.containers[].image] | unique | .[]' pods.json
```

```text
busybox:1.36
nginx:1.26
nginx:1.27
```

Count Pods per phase:

```bash
jq -r '.items | group_by(.status.phase) | .[] | "\(.[0].status.phase) \(length)"' pods.json
```

```text
Pending 1
Running 3
```

Find Pods whose containers have restarted. The `?` after `[]` matters: a Pod that has not started yet has no `containerStatuses`, and without `?` jq stops with an error.

```bash
jq -r '.items[] | select(any(.status.containerStatuses[]?; .restartCount > 0)) | .metadata.name' pods.json
```

```text
web-prod-2
```

And the opposite: Pods that have no `containerStatuses` yet:

```bash
jq -r '.items[] | select(.status.containerStatuses | not) | .metadata.name' pods.json
```

```text
batch-1
```

### yq

Everything in this book that says `yq` means **mikefarah/yq v4**. Check with `yq --version`; it should say `https://github.com/mikefarah/yq/`.

Read fields (the same path syntax as `jq`):

```bash
yq '.metadata.name' pod.yaml                    # web-prod-1
yq '.spec.containers[0].image' pod.yaml         # nginx:1.27
yq '.items[].metadata.name' pods.yaml           # one name per line
yq '.items[] | select(.metadata.labels.env == "prod") | .metadata.name' pods.yaml
```

```text
web-prod-1
web-prod-2
```

**Edit a file in place** with `-i`. Work on a copy while you are learning:

```bash
cp pod.yaml edit.yaml
yq -i '.spec.containers[0].image = "nginx:1.28"' edit.yaml
yq '.spec.containers[0].image' edit.yaml
```

```text
nginx:1.28
```

Append to a list:

```bash
yq -i '.spec.containers[0].env += [{"name": "APP_MODE", "value": "test"}]' edit.yaml
yq '.spec.containers[0].env' edit.yaml
```

```text
- name: APP_MODE
  value: test
```

Clean up a manifest you exported with `kubectl get -o yaml` so you can reuse it. Remove the server-populated fields:

```bash
yq 'del(.status) | del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp)' pod.yaml
```

```text
apiVersion: v1
kind: Pod
metadata:
  labels:
    env: prod
    tier: web
  name: web-prod-1
  namespace: ch03-kubectl
spec:
  containers:
    - image: nginx:1.27
      name: app
```

(The output continues with the container's `resources` block.) Convert JSON to YAML:

```bash
yq -p=json -o=yaml '.items[0].metadata.labels' pods.json
```

```text
env: prod
tier: web
```

> **Exam tip:** `yq` is the quickest safe way to change one field of a manifest you generated with `$do`, without opening an editor. In the exam, `vim` is still the dependable fallback.

## 5. Discovering the API

The API server describes itself, so you never need a web browser to find a field name or a resource's API version.

```bash
kubectl api-resources                              # every resource type the cluster serves
kubectl api-resources --namespaced=false           # cluster-scoped ones (Nodes, Namespaces, ...)
kubectl api-resources --api-group=apps             # one API group
kubectl api-resources -o wide                      # adds the supported verbs
kubectl api-versions                               # group/version pairs
```

`api-resources` shows NAME, SHORTNAMES (`po`, `svc`, `cm`, `deploy`), APIVERSION (what you write in a manifest), NAMESPACED, and KIND.

`kubectl explain` prints the documentation for any field, taken from *your cluster's* API:

```bash
kubectl explain pod
kubectl explain pod.spec.containers
kubectl explain pod.spec.terminationGracePeriodSeconds
kubectl explain pod.spec.containers --recursive     # the whole field tree, no descriptions
```

The header line shows the field and its type (for example `<integer>` or `<[]Container>`); the description follows. `--recursive` is the fastest way to remember the shape of a block (what goes under `securityContext`, say) without leaving the terminal.

For raw access, `kubectl get --raw /apis` and `kubectl get --raw /version` call the API server directly.

> **Exam tip:** `kubectl explain` is faster than searching the documentation for a field name, and it matches the exam cluster's version exactly.

## 6. Creating things

### Imperative commands

Imperative commands build an object from flags. They are fast, and with `--dry-run=client -o yaml` they print the manifest instead of creating anything.

```bash
kubectl run web --image=nginx:1.27 --port=80 --labels=app=web
kubectl run probe --image=busybox:1.36 --labels=role=probe --command -- sleep 3600
kubectl run once --image=busybox:1.36 --restart=Never -- echo "hello"
kubectl run envpod --image=busybox:1.36 --env=APP_MODE=test --command -- sleep 3600

kubectl create configmap app-config --from-literal=APP_MODE=prod --from-literal=LOG_LEVEL=info
kubectl create secret generic db-pass --from-literal=password=hunter2
kubectl create serviceaccount robot
kubectl create namespace staging

kubectl expose pod web --port=80          # a Service selecting the Pod's labels
```

Notes on `kubectl run`:

- Everything after `--` is the container's command or arguments. With `--command` it becomes the **command** (replacing the image's entrypoint); without it, it becomes the **arguments**.
- `--restart=Never` makes a Pod that is not restarted when it exits (Chapter 04 covers restart policies).
- There are no flags for resource requests and limits; you add those in YAML.

### Generate, edit, apply

The fastest reliable workflow under time pressure:

```bash
kubectl run web --image=nginx:1.27 --labels=app=web --dry-run=client -o yaml > web.yaml
vim web.yaml                      # or: yq -i '...' web.yaml
kubectl apply -f web.yaml
```

`--dry-run=client` builds the object **on your machine** and sends nothing. `--dry-run=server` sends it to the API server, which validates it and applies defaults and admission rules but does **not** save it, so it catches errors that client mode cannot.

The same generator works for kinds you meet in later chapters. This chapter only shows their output; you apply them in Chapter 05 and Chapter 08:

```bash
kubectl create deployment web --image=nginx:1.27 --replicas=3 --dry-run=client -o yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  creationTimestamp: null
  labels:
    app: web
  name: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  strategy: {}
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: web
    spec:
      containers:
      - image: nginx:1.27
        name: nginx
        resources: {}
status: {}
```

*(Example output. The `creationTimestamp: null`, `strategy: {}`, `resources: {}`, and `status: {}` lines are harmless noise from the generator.)*

## 7. Changing things

### `create`, `apply`, `replace`, `edit`, `patch`

| Command | What it does | Use when |
|---|---|---|
| `kubectl create -f file` | Creates; **fails** if the object already exists | You want an error on duplicates |
| `kubectl apply -f file` | Creates or updates to match the file | The usual declarative workflow, repeatable |
| `kubectl replace -f file` | Replaces the whole object; fails if it does not exist | You are sure it exists and want the file to be the whole truth |
| `kubectl replace --force -f file` | Deletes and recreates | A change touches an immutable field (Chapter 04 explains which) |
| `kubectl edit pod web` | Opens the live object in your editor | A quick manual change |
| `kubectl patch ...` | Changes just the fields you give | Scripted or one-field changes |

`apply` records what *you* last applied (client-side apply stores it in an annotation) so it can work out what to change. `kubectl apply --server-side` lets the API server track which tool owns each field instead; you do not need it yet, but you will see "field manager" and "conflict" messages when two tools edit the same object.

**`patch`** takes a fragment. There are three styles:

```bash
# strategic merge patch (the default): lists merge by key, so name the container
kubectl patch pod web -p '{"spec":{"containers":[{"name":"web","image":"nginx:1.27"}]}}'

# JSON merge patch: simple objects, but lists are replaced whole
kubectl patch pod web --type=merge -p '{"metadata":{"labels":{"tier":"front"}}}'

# JSON patch: explicit operations on paths
kubectl patch pod web --type=json -p '[{"op":"replace","path":"/spec/containers/0/image","value":"nginx:1.27"}]'
```

Most Pod fields cannot be changed on a running Pod (Chapter 04 explains which); the image is one of the few that can.

**`diff`** shows what `apply` *would* change, without changing it:

```bash
kubectl diff -f web.yaml
```

It exits with status 1 when there are differences (and greater than 1 on a real error), so it works in scripts.

### Labels and annotations

```bash
kubectl label pod web tier=front                 # add a label
kubectl label pod web tier=backend --overwrite   # change an existing one (required)
kubectl label pod web tier-                      # a trailing dash REMOVES the label
kubectl label pods -l env=dev stage=test         # a selector applies it to many Pods
kubectl annotate pod web contact=ops
kubectl annotate pods -l tier=db reviewed=true
```

Changing an existing label or annotation without `--overwrite` is an error, so a copy-paste can never silently replace a value.

### Setting the image, deleting, waiting

```bash
kubectl set image pod/web web=nginx:1.27         # CONTAINER=IMAGE; look the container name up first
kubectl delete pod web                           # graceful: SIGTERM, then SIGKILL after the grace period
kubectl delete pod web --now                     # same as --grace-period=1
kubectl delete pod web --force --grace-period 0  # remove the API object immediately
kubectl delete pods -l env=dev                   # by selector
kubectl delete pod junk --ignore-not-found       # no error if it is already gone
```

Use `--force --grace-period 0` only in a lab. It removes the object from the API without waiting for the kubelet to confirm the container has stopped.

`kubectl wait` blocks until a condition holds, which is better than guessing with `sleep`:

```bash
kubectl wait --for=condition=Ready pod/web --timeout=60s
kubectl wait --for=delete pod/web --timeout=60s
```

### Commands that need a controller

`kubectl scale`, `kubectl set env`, `kubectl set resources`, and `kubectl rollout` work on controllers such as Deployments, not on bare Pods. You practise them from Chapter 05. For now, know that `kubectl scale --replicas=3 deployment/web` is how you change a Deployment's replica count, and that none of these can modify a plain Pod's environment or resources (you edit the YAML and recreate the Pod).

## 8. Permissions: `kubectl auth can-i`

Ask the API server whether an identity may do something:

```bash
kubectl auth can-i create pods                          # you, in the current namespace
kubectl auth can-i delete pods -n kube-system
kubectl auth can-i list secrets --as=system:serviceaccount:ch03-b3:viewer -n ch03-b3
kubectl auth can-i --list -n ch03-b3                    # everything you can do there
```

Two details to remember:

- The answer is printed as `yes` or `no`, **and the exit status is 0 for yes and 1 for no**. In a script with `set -e` or `pipefail`, a "no" will stop the script unless you handle it (`|| true`).
- `--as` impersonates a user or ServiceAccount. A ServiceAccount's name has the form `system:serviceaccount:NAMESPACE:NAME`. You can only impersonate if you have permission to; the lab cluster's admin does.

`can-i` reports what RBAC currently allows. How permissions are granted (Roles, ClusterRoles, and bindings) is Chapter 23.

## 9. The fast terminal

On a timed exam, every command you type costs seconds. A few habits remove most of the typing.

### What the exam gives you, and what to practise with

The Linux Foundation's published exam instructions (checked while writing this chapter; read the current version before your exam) say the CKA and CKAD run on designated hosts you reach with `ssh`, and that those hosts already have `kubectl` with the **`k` alias and Bash completion**, `yq`, `curl`, `wget`, and `man` pages. Nested `ssh` is not supported, so after you `ssh` to a node for a task you `exit` back before the next one. They allow the official Kubernetes documentation (and, for the CKA, the Gateway API docs), and describe copy and paste in the exam terminal as `Ctrl+Shift+C` and `Ctrl+Shift+V`. The CKA and CKAD each have 15 to 20 tasks in two hours. The CKA environment was on Kubernetes v1.35 and the CKAD on v1.37 when this chapter was written, which is why the book pins v1.35: small differences between versions are normal, so run `kubectl version` first.

You therefore do not need to build the alias and completion *in* the exam, but you do need to be fast with them there, and you should practise with the same setup at home. `envs/shell/` in this repository gives you that:

| File | What it does |
|---|---|
| `kubectl-exam.sh` | `alias k=kubectl`, completion for `kubectl` and `k`, `$do`, `$now`, `KUBE_EDITOR`, and the `kn` helper |
| `vimrc` | Two-space indentation and `expandtab` (YAML forbids tabs) |
| `install.sh` / `uninstall.sh` | Add or remove one clearly marked block in your rc file and `~/.vimrc` |

```bash
envs/shell/install.sh --print      # shows exactly what it would add; changes nothing
envs/shell/install.sh              # adds the marked blocks (one-time backups: FILE.kbook-backup)
envs/shell/uninstall.sh            # removes them again
```

Linux, macOS, and WSL2 are supported. Bash needs the `bash-completion` package (`sudo apt-get install bash-completion`; on macOS use a current Bash plus `bash-completion@2`, or use zsh).

### Aliases and variables

```bash
alias k=kubectl
export do="--dry-run=client -o yaml"
export now="--force --grace-period 0"
```

```bash
k run web --image=nginx:1.27 $do > web.yaml      # generate a manifest
k delete pod web $now                            # delete immediately (lab only)
```

In zsh an unquoted variable is not split into words, so write `${=do}` and `${=now}` there. `kn demo` sets the default namespace of the current context to `demo` (it runs `kubectl config set-context --current --namespace=demo`).

Completion matters more than the alias: with it, `k get po<Tab>` completes resource names, `k -n k<Tab>` completes namespaces, and `k explain pod.spec.<Tab>` completes fields.

### Editing YAML in `vim`

The most important settings are in `envs/shell/vimrc`:

```vim
set expandtab tabstop=2 shiftwidth=2 softtabstop=2
```

Without them, pressing Tab puts a real tab character into YAML, which is invalid. Fast `vim` moves worth knowing: `i` insert, `Esc` leave insert mode, `:wq` save and quit, `:q!` quit without saving, `dd` delete a line, `yy` copy a line, `p` paste, `u` undo, `/text` search, `n` next match, `:set paste` before pasting a block (so it is not auto-indented), `>>` indent a line and `5>>` indent five lines. `KUBE_EDITOR` decides which editor `kubectl edit` opens.

### History and shortcuts

`Ctrl-r` searches your command history, `Ctrl-a`/`Ctrl-e` jump to the start/end of the line, `Ctrl-w` deletes a word (in the exam terminal, use `Ctrl+Alt+W` instead, because the browser reserves `Ctrl+W`), `!!` repeats the last command, and `!$` is its last word.

### Optional: `tmux`

`tmux` splits one terminal into panes, which is handy for keeping `kubectl get pods -w` open next to your editor. It is **not** listed among the exam tools, so treat it as a home-practice convenience.

```bash
tmux                      # start; Ctrl-b % splits left/right, Ctrl-b " top/bottom, Ctrl-b o moves
cat > ~/.tmux.conf <<'CONF'
set -g mouse on
set -g history-limit 20000
bind | split-window -h
bind - split-window -v
CONF
```

### Bookmark, then practise

The exam allows the official documentation, so learn where things are before the exam, not during it. The *kubectl Quick Reference* page is the most useful single page to know. Practise finding the others you need (for example the page for a Pod's `securityContext` fields). Use `kubectl explain` first; it is faster.

## Hands-on lab

The lab works like a KodeKloud lab: one task at a time, a check after each,
and progress that is saved between sessions. It has **six parts**. They are
independent: each has its own namespaces, tasks, solution, and reset. Pick a
part with `PART=<part>`; with no `PART`, part `a` runs.

| Part | What it practises | Namespace(s) |
|---|---|---|
| `a` | Selectors, output formats, annotating, generating manifests, `explain`, optional `jq`/`yq` | `ch03-kubectl` |
| `b1` | Contexts | `ch03-b1-a`, `ch03-b1-b` |
| `b2` | Imperative creation of config objects | `ch03-b2` |
| `b2p` | Imperative creation, Pods only | `ch03-b2p` |
| `b3` | Permission checks with `auth can-i` | `ch03-b3` |
| `final` | A timed mini-exam mixing everything | `ch03-f1`, `ch03-f2` |

```bash
make lab CH=3 PART=a            # set up a part and show its first task
make check CH=3 PART=a          # check the current task; if it is right, show the next
make question CH=3 PART=a       # show the current task again
make skip CH=3 PART=a           # move on without checking (for the optional task)
make reset CH=3 PART=a          # back to the starting state and task 1
make verify CH=3 PART=a         # check every task of the part at once
make solve CH=3 PART=a          # reference solution (spoilers!)
make use-namespace CH=3 PART=a  # optional: default kubectl to that part's namespace
make teardown CH=3 PART=a       # remove the part and restore your kubectl settings
```

`b2` and `b2p` practise the same skill. **`b2p` uses only Pods**, which you already know. **`b2` also creates a ConfigMap, a Secret, a ServiceAccount, and a Service**, which later chapters (07 and 11) explain properly; here you only *create* them. Do `b2p` first; do `b2` if you are comfortable, or both for extra practice.

Answers that are files go under `/tmp` on your machine; each task says where. `make reset` and `make teardown` remove them. Debugging a check that fails and you do not know why: `LAB_DEBUG=1 make check CH=3 PART=a` prints a shell trace. Solutions are in [`lab/solutions.md`](lab/solutions.md).

### Part a: shared Pods

The lab created seven Pods in the Namespace `ch03-kubectl`. Look at them first (`kubectl -n ch03-kubectl get pods --show-labels`). **Consider only those seven Pods when you answer; ignore any Pod you create yourself,** so the order you do the tasks in does not matter.

#### Task A1: Label selectors

Save the names of the Pods labelled `env=prod` **and** `tier=web`.

- File: `/tmp/ch03-a1.txt`
- Format: one name per line

#### Task A2: Names and images

Save one line per Pod: the Pod's name, then its image, separated by a space.

- File: `/tmp/ch03-a2.txt`
- Format: `NAME IMAGE`, one Pod per line

#### Task A3: Set-based selectors

Save the names of the Pods whose `env` label is **not** `prod`. That includes any Pod that has no `env` label at all.

- File: `/tmp/ch03-a3.txt`
- Format: one name per line

#### Task A4: Annotate by selector

Annotate every Pod that has the label `tier=db`.

- Annotation: `reviewed=true`
- Pods: every Pod with `tier=db`, and no other Pod

#### Task A5: Generate, then create

Generate a manifest **without creating the Pod**, save it, then create the Pod from that file.

- Name: `api`
- Image: `nginx:1.27` (a single container)
- Label: `app=api`
- Manifest file: `/tmp/ch03-api.yaml`

#### Task A6: Ask the API

Use the cluster's own documentation to find the *type* of the field `terminationGracePeriodSeconds` in a Pod's spec.

- File: `/tmp/ch03-a6.txt`
- Content: the single word (for example `string`)

#### Task A7: jq or yq (optional)

Using `jq` on `-o json` output, or `yq` on `-o yaml` output, save the sorted, unique list of container images the Pods use.

- File: `/tmp/ch03-a7.txt`
- Format: one image per line

This task is optional: skip it with `make skip CH=3 PART=a` if you do not have the tools.

### Part b1: contexts

Two Namespaces exist, `ch03-b1-a` and `ch03-b1-b`. Each contains a ConfigMap named `where` whose `value` is a random string. The two ConfigMaps have the same name; the context decides which one you read. `make teardown CH=3 PART=b1` removes your contexts and restores the context and namespace you had.

#### Task B1.1: Create a context

Create a context that uses the **same cluster and user** as the context you are using now (see `kubectl config view`).

- Context name: `ch03-a`
- Default namespace: `ch03-b1-a`

#### Task B1.2: Create another context

Create a second context the same way.

- Context name: `ch03-b`
- Default namespace: `ch03-b1-b`

#### Task B1.3: Read through a context

Read the `value` of the ConfigMap `where` **through the context `ch03-a`** and save it.

- File: `/tmp/ch03-b1-a.txt`

You may switch contexts or use `--context`; both work.

#### Task B1.4: Read through the other context

Do the same through the context `ch03-b`.

- File: `/tmp/ch03-b1-b.txt`

### Part b2p: imperative creation, Pods only

The Namespace `ch03-b2p` has two Pods, `web` and `junk`.

#### Task P1: Run a Pod in one command

In one command, create a Pod that runs `sleep 3600`.

- Name: `probe`
- Image: `busybox:1.36` (a single container)
- Label: `role=probe`
- Command: `sleep 3600`

#### Task P2: A Pod that runs once

Create a Pod that prints a message once and is **not** restarted.

- Name: `hello`
- Output: `hello from ch03`

#### Task P3: Label and annotate

Add a label and an annotation to the Pod `web`.

- Label: `tier=front`
- Annotation: `contact=ops`

#### Task P4: Change the image in place

Change the image of the Pod `web` **without recreating it** (the check compares the Pod's unique ID).

- New image: `nginx:1.27`

#### Task P5: Environment variables

Create a Pod that sleeps and has an environment variable.

- Name: `envpod`
- Image: `busybox:1.36` (a single container)
- Environment variable: `APP_MODE=test`

#### Task P6: Delete fast

Delete the Pod `junk` quickly. Leave `web` alone.

### Part b2: imperative creation, config objects

The Namespace `ch03-b2` has a running Pod `web` (label `app=web`).

#### Task C1: ConfigMap

- Name: `app-config`
- Data: `APP_MODE=prod`, `LOG_LEVEL=info`

#### Task C2: Secret

- Type: generic
- Name: `db-pass`
- Data: `password=hunter2`

#### Task C3: ServiceAccount

- Name: `robot`

#### Task C4: A Pod that runs once

Create a Pod that prints a message once and is not restarted.

- Name: `hello` (a single container)
- Output: `hello from ch03`

#### Task C5: Service

Expose the Pod `web` as a Service.

- Service name: `web`
- Port: `80`

### Part b3: permissions

The Namespace `ch03-b3` has a ServiceAccount `viewer` bound to the built-in `view` role in that Namespace only.

#### Task B3: Permissions

Answer these four questions **about that ServiceAccount**, in this order, one word per line (`yes` or `no`):

1. Can it delete Pods in `ch03-b3`?
2. Can it list Secrets in `ch03-b3`?
3. Can it get Pods in `ch03-b3`?
4. Can it list Pods in the Namespace `kube-system`?

- File: `/tmp/ch03-b3.txt`

Use `kubectl auth can-i`; do not guess. The answer is the cluster's, not yours.

### Part final: timed mini-exam

This part is a dress rehearsal for the exam, in the style of the killer.sh
simulator, so it works differently from the other parts. There are no
step-by-step checks: you get all six questions at once, answer them in any
order, and score yourself with `make verify CH=3 PART=final` when you are
done. Each question has a task weight and counts only when everything it asks
for is right; the lab is complete at 100%.

The clock starts when `make lab CH=3 PART=final` finishes. Your target is **20
minutes**; `make verify` reports the time you used but never fails you for
being slow. Pods only, and no `jq` or `yq`. Answer files go under
`/tmp/kbook/ch03-final/<question>/`; the folders already exist.

#### Question 1 | Run a labelled Pod

Task weight: 15%

Use context: `kubectl config use-context kind-kbook`

Create a Pod named `sleeper` in Namespace `ch03-f1` with a single container of
image `busybox:1.36` that runs `sleep 3600`, and the label `team=blue`.

#### Question 2 | Select by label

Task weight: 15%

Use context: `kubectl config use-context kind-kbook`

Write the names of the Pods in Namespace `ch03-f1` labelled `team=red` into
`/tmp/kbook/ch03-final/2/pods`.

#### Question 3 | Relabel

Task weight: 20%

Use context: `kubectl config use-context kind-kbook`

In Namespace `ch03-f2`, change the label `stage=old` to `stage=new` on every
Pod that has it. The Pod with `stage=keep` must not change.

#### Question 4 | Change an image in place

Task weight: 15%

Use context: `kubectl config use-context kind-kbook`

Change the image of the Pod `x1` in Namespace `ch03-f2` to `nginx:1.27`
without recreating it. Look up the container's name first.

#### Question 5 | Generate, then create

Task weight: 20%

Use context: `kubectl config use-context kind-kbook`

Generate (with `--dry-run=client -o yaml`) a manifest for a Pod named `gen`
with a single container of image `busybox:1.36` that runs `sleep 3600` and has
the environment variable `FOO=bar`, into `/tmp/kbook/ch03-final/5/gen.yaml`.
Then create the Pod in Namespace `ch03-f2` from that file.

#### Question 6 | Find by image

Task weight: 15%

Use context: `kubectl config use-context kind-kbook`

Write the name of the one Pod in Namespace `ch03-f1` whose image is
`nginx:1.26` into `/tmp/kbook/ch03-final/6/pod`.

## Exam tips

> **Exam tip:** Generate, do not type. `k run ... $do > x.yaml`, edit with `yq -i` or `vim`, then `k apply -f x.yaml`. Writing a manifest from memory is the slowest and most error-prone way.

> **Exam tip:** Check the result of every task before moving on: `k get`, `k describe`, or `k auth can-i`. A command that printed no error may still not have done what you meant.

> **Exam tip:** Always pass `-n` and always run the context command a task gives you. Wrong cluster or wrong namespace costs tasks you actually solved.

> **Exam tip:** Do not get stuck. With 15 to 20 tasks in two hours you have about six to eight minutes per task on average. Skip a hard task, come back to it, and remember that some tasks are worth more than others.

> **Exam tip:** `kubectl explain` and `kubectl api-resources` answer "what is the field or `apiVersion`" faster than any web page, and they match the exam cluster's version.

## Common mistakes

- Forgetting `--overwrite` when changing a label, then assuming the old value changed.
- Using `-l env!=prod` and being surprised that Pods **without** an `env` label are included.
- Reading `kubectl get all` as "everything".
- Saving `kubectl get -o name` output (`pod/web`) where bare names were expected.
- Piping `kubectl auth can-i` into a script that exits on a non-zero status: "no" is exit status 1.
- Putting a real tab into YAML.
- Editing a context's namespace and forgetting you did, then wondering why `kubectl get pods` shows nothing.

<!-- QUESTIONS:START -->

## End-of-chapter questions

**1.** `CKA` `CKAD` Which command changes the default namespace of the context you are currently using?

- **A.** kubectl config set-context --current --namespace=dev
- **B.** kubectl config use-context dev
- **C.** kubectl set namespace dev
- **D.** kubectl config set-cluster dev

**2.** `CKA` `CKAD` A namespace has Pods labelled env=prod, Pods labelled env=dev, and Pods with no env label. Which Pods does `kubectl get pods -l env!=prod` return?

- **A.** Only the env=dev Pods
- **B.** The env=dev Pods and the Pods with no env label
- **C.** Only the Pods with no env label
- **D.** No Pods; `!=` is not valid in a label selector

**3.** `CKA` `CKAD` A Pod named `web` already exists. What happens when you run `kubectl create -f web.yaml` and then `kubectl apply -f web.yaml` for the same Pod?

- **A.** Both succeed and update the Pod
- **B.** `create` fails because the object exists; `apply` succeeds and updates it to match the file
- **C.** `create` updates the Pod; `apply` fails
- **D.** Both fail because the Pod already exists

**4.** `CKA` `CKAD` What is the difference between `--dry-run=client` and `--dry-run=server`?

- **A.** There is none; they are aliases
- **B.** `client` builds the object locally and sends nothing; `server` sends it to the API server, which validates it and applies defaults and admission rules, but does not store it
- **C.** `client` stores the object; `server` does not
- **D.** `server` can only be used with `kubectl run`

**5.** `CKA` `CKAD` `kubectl auth can-i delete pods -n prod` prints `no`. What exit status does the command return?

- **A.** 0
- **B.** 1
- **C.** 2
- **D.** It always returns 0 so that scripts do not stop

**6. (Task)** `CKA` `CKAD` In namespace `dev`, print the names of the Pods whose `tier` label is `web` or `cache`, one per line, with no `pod/` prefix.

**7. (Task)** `CKA` `CKAD` List every Pod in the current namespace as two columns, NAME and NODE, sorted by node name.

**8. (Task)** `CKA` `CKAD` Switch to the context `staging`, then make `payments` the default namespace for that context.

**9. (Task)** `CKA` `CKAD` Generate, without creating it, a manifest for a Pod named `batch` with one container running `busybox:1.36` that executes `sleep 600`, save it as `batch.yaml`, then create the Pod from the file.

**10. (Task)** `CKA` `CKAD` In namespace `dev`, set the label `release=stable` on every Pod labelled `app=api`, replacing the label's value on Pods that already have a different `release` value.

**11. (Task)** `CKA` `CKAD` Block until Pod `web` is Ready, but give up after 90 seconds.

**12. (Task)** `CKA` List the resource types that are cluster-scoped, that is, not namespaced.

**13. (Task)** `CKA` `CKAD` Print only the value of the annotation `owner` of Pod `web`.

**14. (Task)** `CKA` Check whether the ServiceAccount `build` in namespace `ci` is allowed to create Deployments in namespace `ci`.

**15. (Task)** `CKA` `CKAD` Optional (uses `yq`, which the exam hosts have; `jq` is not guaranteed there). The file `pod.yaml` contains a Pod. Change the image of its first container to `redis:7` in place, without opening an editor.

<details>
<summary>Answers</summary>

**1. A.** `set-context --current --namespace=...` edits the current context. `use-context` switches to a different context, there is no `kubectl set namespace`, and `set-cluster` edits a cluster entry, not a namespace.

**2. B.** `!=` matches every object whose `env` label is not `prod`, which includes objects that have no `env` label at all. `env notin (prod)` behaves the same way. Use `-l 'env,env!=prod'` to require that the label exists.

**3. B.** `create` only creates and returns an AlreadyExists error otherwise. `apply` creates the object if it is missing and updates it to match the file if it exists (as far as the Pod's mutable fields allow).

**4. B.** Client mode never contacts the API server for the object, so it cannot catch errors that only the server knows about. Server mode runs the real validation and admission path and stops just before persisting.

**5. B.** `can-i` prints yes or no and returns 0 for yes and 1 for no. In a script with `set -e` or `pipefail`, a `no` stops the script unless you handle it, for example with `|| true`.

**6.**

```bash
kubectl -n dev get pods -l 'tier in (web,cache)' \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
```

`-o name` also works but prints `pod/NAME`. Strip the prefix with `sed 's#^pod/##'`, or use the JSONPath form above.

**7.**

```bash
kubectl get pods \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName \
  --sort-by=.spec.nodeName
```

`--sort-by` takes a JSONPath-style field of the objects being listed.

**8.**

```bash
kubectl config use-context staging
kubectl config set-context --current --namespace=payments
```

Confirm with `kubectl config view --minify | grep namespace`.

**9.**

```bash
kubectl run batch --image=busybox:1.36 --dry-run=client -o yaml \
  --command -- sleep 600 > batch.yaml
kubectl apply -f batch.yaml
```

`--command` makes `sleep 600` the container's command; everything after `--` belongs to the container, so the kubectl flags must come first.

**10.**

```bash
kubectl -n dev label pods -l app=api release=stable --overwrite
```

Without `--overwrite`, kubectl refuses to change a label that already has a different value.

**11.**

```bash
kubectl wait --for=condition=Ready pod/web --timeout=90s
```

The command returns non-zero if the condition is not met in time.

**12.**

```bash
kubectl api-resources --namespaced=false
```

Examples in the output include Nodes, Namespaces, PersistentVolumes, and ClusterRoles.

**13.**

```bash
kubectl get pod web -o jsonpath='{.metadata.annotations.owner}{"\n"}'
```

For an annotation key that contains dots or slashes, escape the dots: `{.metadata.annotations.example\.com/owner}`.

**14.**

```bash
kubectl auth can-i create deployments -n ci --as=system:serviceaccount:ci:build
```

A ServiceAccount's user name has the form `system:serviceaccount:NAMESPACE:NAME`. The command prints `yes` or `no`.

**15.**

```bash
yq -i '.spec.containers[0].image = "redis:7"' pod.yaml
```

This is mikefarah/yq v4. Check with `yq '.spec.containers[0].image' pod.yaml`. Without `yq`, `sed -i 's#image: .*#image: redis:7#' pod.yaml` works for a file with a single `image:` line, but it is easy to get wrong in a file with several containers.

</details>

<!-- QUESTIONS:END -->

## Further reading

- Kubernetes documentation: *kubectl Quick Reference*, *Organize Cluster Access Using kubeconfig Files*, *JSONPath Support*, *Labels and Selectors*, *Field Selectors*
- The `jq` manual (jqlang.org) and the `yq` documentation (mikefarah.gitbook.io/yq)
- The Linux Foundation's *Important Instructions: CKA and CKAD* page, read again before your exam
- Appendix: [`appendices/kubectl-cheatsheet.md`](../../appendices/kubectl-cheatsheet.md)
- Chapter 04 and Chapter 05 next: Pods in depth, then the controllers that manage them
