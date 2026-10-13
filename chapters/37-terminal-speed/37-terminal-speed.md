# Chapter 37: Terminal speed: drills for aliases, vim, tmux, jq and yq, and imperative commands

> **Exams:** CKAD · CKA
> **Difficulty:** Intermediate
> **Time:** ~30 min reading, ~40 min drills
> **Lab tier:** 1 (kind)
> **Prerequisites:** Chapter 03 (kubectl fluency: contexts, output formats, jq and yq, imperative commands)

## Learning objectives

After this chapter you can:

- Find the shortest correct kubectl command for a task by using short names, generators, and output filters
- Generate a manifest with a client-side dry run, change it with `yq`, and apply it, without writing YAML from scratch
- Use `jq` and `yq` to pull exactly the values a task asks for into a file
- Edit a YAML file in `vim` with the handful of motions that cover most exam edits
- Use history, shell shortcuts, and `tmux` panes so that you type less and look up less
- Measure your own speed on a drill, and find the step that costs the most time

## Concepts

### Where the time goes

Under time pressure, most lost minutes are not typing. They are:

1. **Looking up** a field name, a flag, or a resource's short name
2. **Reading** output that is too long to scan
3. **Fixing** a typo or an indentation error that a check then reports
4. **Waiting** for something you could have checked in one command

Chapter 03 gave you the tools. This chapter turns them into habits, by drilling each one
until it is automatic. The lab at the end is a drill: each task is an ordinary exam
action, and its check tells you at once whether you did it.

The CKA and CKAD give 15 to 20 tasks in two hours. That is about six to eight minutes a task,
so a task that takes twelve minutes is a task you should have flagged and skipped (Chapter 03).

### Short names and the `k` alias

Every resource has a short name, and the shortest correct form is the fastest to type.

```text
pods            po         deployments     deploy     services          svc
namespaces      ns         configmaps      cm         persistentvolumeclaims   pvc
replicasets     rs
```

These short names come from `kubectl api-resources`, and they work with every verb. `k` is
an alias for `kubectl` in the exam environment. Setting it up at home is one of the steps
in `envs/shell/` (Chapter 03, section 9).

> **Exam tip:** Type `k get deploy` rather than `kubectl get deployments`. Over a day of drills, the difference is measurable, and the exam rewards it.

### Generate, do not write

Most objects can be generated with a flag. The command that generates a manifest is the
same command that creates the object, with `--dry-run=client -o yaml` added. A client-side
dry run creates nothing, so you can generate, inspect, edit, and only then apply.

```bash
kubectl create deployment web --image=nginx:1.27 --replicas=3 --dry-run=client -o yaml > web.yaml
```

Use `kubectl explain` for a field you do not remember, and add `--recursive` to see the whole
tree of a type at once. `kubectl explain pod.spec.restartPolicy` answers the question in one
screen, and it is faster than the documentation.

> **Exam tip:** Generate first, then change only what the task asks for. A generated Deployment already has the selector and the labels the API requires, and writing those by hand is where most errors come from.

### Filter the output, do not read it

When you need a value, ask for it. `-o jsonpath` prints one field, `-o custom-columns` makes a table
of the fields you choose, and `-o wide` adds a few useful columns. For lists that need
filtering, `jq` is shorter than a jsonpath range, and `yq` edits YAML files in place.

| Need | Command shape |
| --- | --- |
| One field of one object | `k get pod web -o jsonpath='{.status.podIP}'` |
| A list of names, one per line | `k get pods -o name` |
| Several fields as a table | `k get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName` |
| A filter over JSON | `k get pods -o json \| jq -r '.items[] \| select(.status.containerStatuses[0].restartCount > 0) \| .metadata.name'` |
| Change a value in a YAML file | `yq -i '.spec.replicas = 5' deploy.yaml` |

Chapter 03 gives the full `jq` and `yq` reference. The drill in this chapter asks you to
choose the shortest form that gives the right answer.

### Edit in vim with a few motions

Most edits in an exam are small. Learn these, in this order, and you can make almost any change
to a YAML file without moving the mouse:

| Keys | Action |
| --- | --- |
| `/text`, then `n` | Search forward, then the next match |
| `dd`, `yy`, `p` | Delete a line, copy a line, paste it below |
| `o`, `O` | Open a new line below or above, and start typing |
| `A`, `I` | Append at the end of the line, or insert at its start |
| `ciw` | Change the word under the cursor |
| `:%s/old/new/g` | Replace every `old` in the file |
| `u`, `Ctrl+r` | Undo, redo |
| `:set ts=2 sw=2 et` | Two-space indentation with spaces (the `envs/shell/vimrc` settings) |
| `:wq` or `:x` | Save and quit |

Indentation is the usual problem. With `expandtab` and two spaces, a YAML fix is a few
keystrokes. Set `KUBE_EDITOR` (done by `envs/shell/kubectl-exam.sh`) so that `kubectl edit` uses
the same settings.

### History and shell shortcuts

The shell remembers what you typed. These keys save the most typing:

- `Ctrl+r`, then a few letters: search the history for the last command that matches
- `!!`: repeat the last command, for example after forgetting `sudo`
- `!$`: the last argument of the previous command, useful for a file you just created
- `Alt+.`: insert the last argument, and press it again to step back through earlier ones
- `Ctrl+a`, `Ctrl+e`: jump to the start or end of the line

### tmux: one pane for the task, one for the docs

`tmux` splits one terminal into panes and windows, so that you can keep a manifest open in
one pane and run `kubectl explain` in another. The default prefix is `Ctrl+b`:

| Keys | Action |
| --- | --- |
| `Ctrl+b %` | Split the window left and right |
| `Ctrl+b "` | Split the window top and bottom |
| `Ctrl+b o` | Move to the next pane |
| `Ctrl+b z` | Zoom the current pane to full screen, and back |
| `Ctrl+b c`, `Ctrl+b n`, `Ctrl+b p` | New window, next window, previous window |
| `Ctrl+b d` | Detach, and leave everything running |

`tmux` is optional. The exam terminal is not yours to configure, so treat `tmux` as a
practice tool for your own machine, and check the current exam instructions before you rely on it.

## Drills

Each drill is a task you will meet in an exam, in a shape that a check can test. A drill
that you finish quickly is one you can trust; a drill you finish slowly shows you what to
practise next. Time yourself with `time` or a phone, and note the drills that cost you most.

- **Run the drill once, untimed**, and read the whole chapter's habits before you start.
- **Run it again, timed.** Write down the time, and the step that cost the most.
- **Repeat until the time stops falling.** Then move to the next drill.

## Guided walkthrough

These steps only read or generate output. None of them creates an object in the cluster.

### Short names

```bash
kubectl api-resources | awk 'NR==1 || $1 ~ /^(pods|deployments|services|namespaces|configmaps|persistentvolumeclaims|replicasets)$/'
```

```text
NAME                                SHORTNAMES   APIVERSION                          NAMESPACED   KIND
configmaps                          cm           v1                                  true         ConfigMap
namespaces                          ns           v1                                  false        Namespace
persistentvolumeclaims              pvc          v1                                  true         PersistentVolumeClaim
pods                                po           v1                                  true         Pod
services                            svc          v1                                  true         Service
deployments                         deploy       apps/v1                             true         Deployment
replicasets                         rs           apps/v1                             true         ReplicaSet
```

The `SHORTNAMES` column is the list to memorize. A resource with no short name is typed in full.

### Generate a Deployment

```bash
kubectl create deployment web --image=nginx:1.27 --replicas=3 --dry-run=client -o yaml
```

```text
apiVersion: apps/v1
kind: Deployment
metadata:
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
      labels:
        app: web
    spec:
      containers:
      - image: nginx:1.27
        name: nginx
        resources: {}
status: {}
```

The selector and the template labels are already consistent. The `strategy`, `resources`,
and `status` fields are empty placeholders you can remove or fill in.

### Look up a field

```bash
kubectl explain pod.spec.restartPolicy
```

```text
KIND:       Pod
VERSION:    v1

FIELD: restartPolicy <string>
ENUM:
    Always
    Never
    OnFailure
```

`kubectl explain` shows the type and the allowed values. Reading it is faster than searching
the documentation for the same field.

## Hands-on lab

The lab works like a KodeKloud lab: one task at a time, a check after each, and
progress that is saved between sessions. It is a drill: the checks test outcomes, so
any command that gets the outcome passes. The point is to do each one fast.

```bash
make lab CH=37       # set up the lab and show task 1
make check CH=37     # check the current task; if it is right, show the next
make question CH=37  # show the current task again
make reset CH=37     # back to the starting state and task 1
make verify CH=37    # check every task at once
```

The lab uses the Namespace `ch37-drill`. The setup starts three Pods: `flaky`, which crashes on
purpose and restarts, and `steady-1` and `steady-2`, which keep running. It also writes a base
Deployment file to `/tmp/ch37/base-deploy.yaml`. The four tasks do not depend on each other.

Full solutions are in [`lab/solutions.md`](lab/solutions.md).

### Task 1: A Deployment, generated and scaled

Create a Deployment named `speed` in Namespace `ch37-drill`, running `nginx:1.27`, with 3
ready replicas. Generate it with a command rather than a manifest you write yourself.

- Deployment `speed` in `ch37-drill`: image `nginx:1.27`, 3 replicas, 3 ready

### Task 2: A Job from a generated manifest

Generate a Job named `count` that runs `busybox:1.36` with the command `sh -c 'echo 1'`. Save
the manifest to `/tmp/ch37/count-job.yaml`, apply that file, and wait until the Job completes.

- File `/tmp/ch37/count-job.yaml`: kind `Job`, name `count`, image `busybox:1.36`
- Job `count` in `ch37-drill` has succeeded once

### Task 3: The Pods that have restarted

Write the names of the Pods in `ch37-drill` that have restarted at least once to
`/tmp/ch37/restarted.txt`, one name per line. Use a filter, not your eyes.

- File `/tmp/ch37/restarted.txt`: the names of the Pods whose container restart count is greater than 0, one per line

### Task 4: A changed copy of a base file

Copy `/tmp/ch37/base-deploy.yaml` to `/tmp/ch37/scaled.yaml`, and change the copy so that it
has 5 replicas. The base file must stay as it is, and the cluster must not be changed.

- File `/tmp/ch37/scaled.yaml`: a Deployment named `shop`, image `nginx:1.27`, 5 replicas
- File `/tmp/ch37/base-deploy.yaml`: still 2 replicas

## Exam tips

> **Exam tip:** Generate with `--dry-run=client -o yaml`, change the file, then apply it. You save the typing of the labels and the selector, and you keep a copy to check.
>
> **Exam tip:** For a value you need, ask for it with `-o jsonpath`, `-o custom-columns`, or `jq`. Reading a full object to find one field costs time you do not get back.
>
> **Exam tip:** Keep one terminal pane for `kubectl explain` and one for the task. Practise the split at home, and use whatever the exam terminal offers when the time comes.

## Common mistakes

- Typing `kubectl get deployments` in full, every time. The short name `deploy` is what you should type.
- Writing a Deployment's YAML from memory, and forgetting the selector or the template labels.
- Expecting `--dry-run=client -o yaml` to write a file. It prints the manifest; redirect the output with `>` to keep it.
- Editing a YAML file with tabs. YAML forbids tabs, so set `expandtab` before you start.
- Scaling the cluster when the task asked for a copy of a file. Read whether the task says "the cluster" or "a file".
- Waiting with `sleep` rather than `kubectl wait --for=...`, which returns as soon as the condition holds.

<!-- QUESTIONS:START -->

## End-of-chapter questions

**1.** `CKAD` `CKA` Which command is the shortest correct way to list Deployments in the current Namespace?

- **A.** kubectl get deployments
- **B.** k get deploy
- **C.** kubectl list deployment
- **D.** k show deployments

**2.** `CKAD` `CKA` What does kubectl create deployment web --image=nginx:1.27 --dry-run=client -o yaml do?

- **A.** Creates the Deployment and prints its YAML
- **B.** Prints the Deployment's YAML without creating it
- **C.** Writes a file named web.yaml in the current directory
- **D.** Validates the image against the registry

**3.** `CKAD` `CKA` Which command shows the allowed values and the type of restartPolicy in a Pod, without searching the documentation?

- **A.** kubectl describe pod restartPolicy
- **B.** kubectl explain pod.spec.restartPolicy
- **C.** kubectl get pod --field restartPolicy
- **D.** kubectl api-resources restartPolicy

**4.** `CKAD` `CKA` You need the name of one Pod's node. Which command is the fastest correct answer?

- **A.** kubectl get pod web -o yaml and then scroll to spec.nodeName
- **B.** kubectl get pod web -o jsonpath='{.spec.nodeName}'
- **C.** kubectl describe pod web and read the whole output
- **D.** kubectl get nodes

**5.** `CKAD` `CKA` Which jq filter prints the names of Pods whose first container has restarted at least once, given kubectl get pods -o json?

- **A.** jq '.items[].metadata.name'
- **B.** jq -r '.items[] | select(.status.containerStatuses[0].restartCount > 0) | .metadata.name'
- **C.** jq '.status.restartCount'
- **D.** jq -r '.items[] | .restartCount'

**6.** `CKAD` `CKA` Which yq command changes the replica count in deploy.yaml, in place?

- **A.** yq '.spec.replicas = 5' deploy.yaml
- **B.** yq -i '.spec.replicas = 5' deploy.yaml
- **C.** yq -r '.spec.replicas' deploy.yaml > 5
- **D.** sed -i 's/replicas: .*/5/' deploy.yaml and then yq -i

**7.** `CKAD` `CKA` In vim, which command replaces every occurrence of old with new in the whole file?

- **A.** :s/old/new
- **B.** :%s/old/new/g
- **C.** ciw old new
- **D.** :replace old new all

**8.** `CKAD` `CKA` Which shell shortcut reuses the last argument of the previous command, such as a file name you just created?

- **A.** !!
- **B.** !$
- **C.** Ctrl+r
- **D.** Alt+a

**9.** `CKAD` `CKA` Which is the most reliable way to wait for a Deployment to finish rolling out in a script?

- **A.** sleep 60
- **B.** kubectl rollout status deployment/web --timeout=120s
- **C.** kubectl get deploy web and check it once
- **D.** kubectl delete pods and hope

**10.** `CKAD` `CKA` Under time pressure, which habit saves the most time on a YAML manifest task?

- **A.** Writing the whole manifest from memory, then applying it
- **B.** Generating the manifest with --dry-run=client -o yaml, changing only what the task asks for, then applying it
- **C.** Copying a manifest from the documentation without reading it
- **D.** Applying the manifest first and fixing it after the check fails

**11. (Task)** `CKAD` `CKA` In Namespace `drill`, create a Deployment named `api` with image `nginx:1.27` and 2 replicas, without writing its YAML by hand. Save the manifest you generated to `/tmp/api.yaml`, then apply it.

**12. (Task)** `CKAD` `CKA` In Namespace `drill`, print the names of the Pods that have a container restarted at least once, one per line, using a filter rather than reading the output by eye.

<details>
<summary>Answers</summary>

**1. B.** deploy is the short name of deployments, and k is the alias for kubectl in the exam environment. The verb is get; list and show are not kubectl verbs.

**2. B.** A client-side dry run prints the object without sending it to the API server. It writes nothing to the cluster, and it does not create a file unless you redirect the output.

**3. B.** kubectl explain prints the type, the allowed values, and a description for any field path. describe shows the state of an object, and the other two commands do not take a field.

**4. B.** jsonpath prints exactly one field, so there is nothing to scan. Reading the full YAML or the describe output costs time without giving a better answer.

**5. B.** The filter selects the items whose restart count is above zero, and prints the name of each. Without select, every name is printed, and the other filters read a field that is not on the Pod object.

**6. B.** yq -i edits the file in place. Without -i, yq prints the changed document to standard output and leaves the file as it was.

**7. B.** The % range covers every line, and the g flag replaces every match on each line. :s on its own affects only the current line, and the first match there.

**8. B.** !$ expands to the last argument of the previous command. !! repeats the whole previous command, and Ctrl+r searches the history.

**9. B.** rollout status waits until the rollout completes or the timeout passes, and it returns an error on failure. A fixed sleep is either too short or wastes time, and one check can run before the rollout starts.

**10. B.** A generated manifest already has the required structure, such as selectors and labels, so you change only what the task asks for. Writing from memory is where most errors come from.

**11.**

```bash
kubectl -n drill create deployment api --image=nginx:1.27 --replicas=2 --dry-run=client -o yaml > /tmp/api.yaml
kubectl apply -f /tmp/api.yaml
```

The `--dry-run=client -o yaml` form prints the manifest, and the redirect keeps it.
`apply` creates the Deployment from that file. Check with `kubectl -n drill get deploy api`.

**12.**

```bash
kubectl -n drill get pods -o json | jq -r '.items[] | select(.status.containerStatuses[0].restartCount > 0) | .metadata.name'
```

`jq -r` prints the names without quotes. The `select` keeps only the Pods whose first
container has a restart count above zero.

</details>

<!-- QUESTIONS:END -->

## Further reading

- The `kubectl` cheat sheet on kubernetes.io, for short names and output formats
- The `jq` manual, and the `yq` documentation for in-place edits
- The `vim` tutor (`vimtutor`), for the motions in this chapter
- The `tmux` manual page, for the keys in this chapter
- Chapter 03 for the full kubectl reference and the exam environment; Chapter 38 for navigating the allowed documentation
