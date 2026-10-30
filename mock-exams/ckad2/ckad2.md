# Mock exam: CKAD simulator, set 2

> **Exam:** CKAD (performance-based style)
> **Covers:** every CKAD domain, weighted as in the curriculum: Application Design and Build 20%, Application Deployment 20%, Application Observability and Maintenance 15%, Application Environment, Configuration and Security 25%, Services and Networking 20%
> **Time:** 120 minutes · **Questions:** 20 · **Pass mark:** 66%
> **Lab tier:** 1 (kind), with Docker and Helm on your path

A second, independent CKAD simulator: 20 new questions, none repeated from set 1
(`mock-exams/ckad`). Take set 1 first; when you retake an exam you remember its
answers, so a fresh set is the honest measure in the last week before the exam.
Like killer.sh, it is meant to be **harder and more hurried than the real exam**.

## How it works

```bash
make cluster                   # once, if you have not already
make mock EXAM=ckad2           # build the exam; the clock starts when it is ready
make mock-score EXAM=ckad2     # score your answers, as often as you like
make mock-reset EXAM=ckad2     # start over from scratch
make mock-teardown EXAM=ckad2  # remove the exam and restore your kubectl settings
```

The rules are those of set 1:

- **Contexts.** The exam creates two contexts, `ckad2-a` and `ckad2-b`. Each
  question names the context to use. Run that command first, every time.
  `ckad2-b` has a default namespace (`ckad2-deploy`); `ckad2-a` does not.
- **Namespaces.** Each question names its Namespace. Use exactly that one.
- **Files.** Files a question starts from, and answers that are files, are under
  `/tmp/kbook/ckad2/<question>/`. Write exactly the file the question names.
- **Tools.** `docker` (question 1) and `helm` (question 7) are on your path.
  Podman works for question 1 too.
- **Documentation.** Allowed: `kubectl explain`, `--help`, and the documentation
  Chapter 38 lists. Not allowed: this book's chapters and the solutions file,
  until you have scored.
- **Weights.** A question counts only when everything it asks for is right; then
  you earn its whole weight.
- **Time.** `make mock-score` shows the time used. It never stops you.

When you are done, run `make mock-score EXAM=ckad2`, then read
[`lab/solutions.md`](lab/solutions.md) for every question you missed.

---

## Question 1 | An image that runs as a user

Task weight: 5%

Use context: `kubectl config use-context ckad2-a`

The directory `/tmp/kbook/ckad2/1/app` holds a Dockerfile and its script. Change the
Dockerfile so that the image runs as user `1000` and declares port `8080/tcp`. Build
it with the tag `ckad2-api:1.1`, and save it in the Docker archive format to
`/tmp/kbook/ckad2/1/ckad2-api.tar`.

---

## Question 2 | An init container fills the web root

Task weight: 5%

Use context: `kubectl config use-context ckad2-a`

In Namespace `ckad2-design`, create a Pod `web-cache` with an init container `fetch`
(image `busybox:1.36`) that writes the text `ckad2 ready` into a file `index.html` on a
shared `emptyDir` volume, and a container `web` (image `nginx:1.27`) that mounts the
same volume at `/usr/share/nginx/html`. The Pod must be Running, and
`/usr/share/nginx/html/index.html` in `web` must contain `ckad2 ready`.

---

## Question 3 | A CronJob with limits

Task weight: 5%

Use context: `kubectl config use-context ckad2-a`

In Namespace `ckad2-design`, create a CronJob `cleanup` that runs `busybox:1.36` with
the command `sh -c 'echo cleaning'` every 15 minutes (`*/15 * * * *`). It keeps the
last 2 successful Jobs and the last failed Job, skips a run that cannot start within
60 seconds of its time, and stops a run after 30 seconds. Its Pods never restart.

---

## Question 4 | A StatefulSet with a claim per replica

Task weight: 5%

Use context: `kubectl config use-context ckad2-a`

In Namespace `ckad2-design`, create a headless Service `kv` (port `80`, selecting
`app=kv`) and a StatefulSet `kv` with 2 replicas of `nginx:1.27` that uses it as its
governing Service. Each replica gets its own `64Mi` claim (access mode
`ReadWriteOnce`, default storage class) from a claim template named `data`, mounted
at `/usr/share/nginx/html`. Both replicas must be ready, and both claims Bound.

---

## Question 5 | Never two versions at once

Task weight: 5%

Use context: `kubectl config use-context ckad2-b`

In Namespace `ckad2-deploy`, the Deployment `reports` must never run old and new Pods
at the same time. Change its strategy accordingly, then update it to `nginx:1.27`.
Both replicas must be available.

---

## Question 6 | Switch from blue to green

Task weight: 5%

Use context: `kubectl config use-context ckad2-b`

In Namespace `ckad2-deploy`, the Service `shop` sends traffic to the Deployment
`shop-blue` (Pods labeled `app=shop`, `version=blue`). `shop-green` (labeled
`version=green`) runs the new release. Switch the Service to green, so that it has
green's 3 Pods as endpoints, then scale `shop-blue` to 0.

---

## Question 7 | Roll back a Helm release

Task weight: 5%

Use context: `kubectl config use-context ckad2-b`

In Namespace `ckad2-deploy`, the latest upgrade of the Helm release `catalog` points
at an image tag that does not exist. Roll the release back to the revision that ran
image tag `1.26`. The release must be `deployed`, with 1 ready replica of
`nginx:1.26`.

---

## Question 8 | A Kustomize overlay with an image and a generator

Task weight: 5%

Use context: `kubectl config use-context ckad2-b`

`/tmp/kbook/ckad2/8/base` is a Kustomize base: a Deployment `web` that reads a
generated ConfigMap `app-config` (`MODE=base`). Create the overlay
`/tmp/kbook/ckad2/8/overlays/staging/kustomization.yaml` that uses the base and:

- puts everything in Namespace `ckad2-deploy`, with the name prefix `staging-`;
- changes the `nginx` image's tag to `1.27`;
- changes `MODE` to `staging` in the generated ConfigMap, by merging into the base's generator.

Apply it. The Deployment `staging-web` must be ready, run `nginx:1.27`, and read a
ConfigMap whose name starts with `staging-app-config-` and whose `MODE` is `staging`.

---

## Question 9 | A removed API version

Task weight: 4%

Use context: `kubectl config use-context ckad2-a`

The manifest `/tmp/kbook/ckad2/9/hpa.yaml` uses an API version the cluster no longer
serves. Change the file to the version the cluster serves for
HorizontalPodAutoscalers, and create the HPA from it.

---

## Question 10 | A slow starter

Task weight: 4%

Use context: `kubectl config use-context ckad2-a`

In Namespace `ckad2-ops`, the Deployment `slow` needs 30 seconds before it creates
`/tmp/ready`, but its liveness probe kills it first. Without changing the liveness
probe, add a startup probe that runs `cat /tmp/ready` every 5 seconds and allows 12
failures. The Deployment must be ready, and its Pod must have no restarts.

---

## Question 11 | Who uses the CPU?

Task weight: 3%

Use context: `kubectl config use-context ckad2-a`

In Namespace `ckad2-ops`, three Pods are labeled `app=load`. Write the name of the one
that uses the most CPU, and nothing else, to `/tmp/kbook/ckad2/11/pod.txt`.

---

## Question 12 | A Pod that never starts

Task weight: 4%

Use context: `kubectl config use-context ckad2-a`

In Namespace `ckad2-ops`, the Pod `api-client` never starts. Find out why, and fix it
without changing the Pod: the value it needs is `http://api`. The Pod must be
Running.

---

## Question 13 | A token for one audience

Task weight: 5%

Use context: `kubectl config use-context ckad2-a`

In Namespace `ckad2-sec`, create a ServiceAccount `reporter` whose token is not
mounted automatically. Create a Pod `reporter` (image `busybox:1.36`, command
`sleep infinity`) that runs as `reporter` and mounts a projected ServiceAccount token
for the audience `reports`, valid for 3600 seconds, as the file
`/var/run/reports/token`. The Pod must be Running.

---

## Question 14 | Read Pods and their logs

Task weight: 5%

Use context: `kubectl config use-context ckad2-a`

In Namespace `ckad2-sec`, create a ServiceAccount `viewer`, a Role `pod-viewer` that
allows `get` and `list` on Pods and reading their logs, and nothing else, and a
RoleBinding `viewer-binding` that gives it to `viewer`.

---

## Question 15 | A TLS Secret from files

Task weight: 5%

Use context: `kubectl config use-context ckad2-a`

In Namespace `ckad2-sec`, create a TLS Secret `web-tls` from the certificate and key
in `/tmp/kbook/ckad2/15/` (`tls.crt`, `tls.key`). Create a Pod `web-tls` (image
`busybox:1.36`, command `sleep infinity`) that mounts the Secret at `/etc/tls`. The
Pod must be Running.

---

## Question 16 | Defaults for every container

Task weight: 5%

Use context: `kubectl config use-context ckad2-a`

In Namespace `ckad2-quota`, create a LimitRange `defaults` that gives every container
without its own values a CPU limit of `200m`, a memory limit of `128Mi`, a CPU request
of `100m`, and a memory request of `64Mi`. Then create a Pod `plain` (image
`busybox:1.36`, command `sleep infinity`) that sets no resources. It must be Running
with those values.

---

## Question 17 | One capability, a read-only root

Task weight: 5%

Use context: `kubectl config use-context ckad2-a`

In Namespace `ckad2-sec`, create a Pod `netadmin` (image `busybox:1.36`, command
`sleep infinity`) whose container drops all capabilities except `NET_ADMIN`, has a
read-only root file system, and gets a writable `emptyDir` volume at `/tmp`. The Pod
must be Running.

---

## Question 18 | Egress to one Service

Task weight: 7%

Use context: `kubectl config use-context ckad2-a`

In Namespace `ckad2-net`, the Pod `frontend` (label `app=frontend`) may only call the
Service `backend` (`wget -qO- http://backend:8080`). Create a NetworkPolicy
`frontend-egress` that allows exactly that, by name, and blocks every other outgoing
connection from `frontend`, for example to the Service `other`.

---

## Question 19 | A NodePort

Task weight: 6%

Use context: `kubectl config use-context ckad2-a`

In Namespace `ckad2-net`, create a Service `legacy-np` of type NodePort for the Pods
of the Deployment `legacy` (label `app=legacy`): port `80` to the container's port
`80`, on node port `30180`. A request to any node's address on port `30180` must
return the nginx page.

---

## Question 20 | An Ingress with TLS and a default backend

Task weight: 7%

Use context: `kubectl config use-context ckad2-a`

In Namespace `ckad2-net`, create an Ingress `portal` with ingress class `nginx`:

- TLS for the host `portal.ckad2.example.test` with the existing Secret `portal-tls`;
- for that host, the path `/api` (path type `Exact`) to the Service `api` on port `80`;
- every other request to the Service `fallback` on port `80`, as the default backend.
