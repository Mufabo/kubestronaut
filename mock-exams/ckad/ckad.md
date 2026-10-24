# Mock exam: CKAD simulator

> **Exam:** CKAD (performance-based style)
> **Covers:** every CKAD domain, weighted close to the curriculum: Application Design and Build 20%, Application Deployment 21%, Application Observability and Maintenance 15%, Application Environment, Configuration and Security 25%, Services and Networking 19%
> **Time:** 120 minutes · **Questions:** 20 · **Pass mark:** 66%
> **Lab tier:** 1 (kind), with Docker and Helm on your path

This is the full CKAD simulator, in the style of killer.sh. Like killer.sh, it is
meant to be **harder and more hurried than the real exam**: 20 questions where the
real exam has 15 to 20. Take it after Parts I and II, Chapters 37 and 38, and the
`part1` and `part2` mock exams; Chapter 39's CKAD plan puts it in the last two
weeks.

## How it works

```bash
make cluster                  # once, if you have not already
make mock EXAM=ckad           # build the exam; the clock starts when it is ready
make mock-score EXAM=ckad     # score your answers, as often as you like
make mock-reset EXAM=ckad     # start over from scratch
make mock-teardown EXAM=ckad  # remove the exam and restore your kubectl settings
```

The rules mirror the real exam environment:

- **Contexts.** The exam creates two contexts, `ckad-a` and `ckad-b`, on your lab
  cluster. Each question names the context to use. Run that command first, every
  time. `ckad-b` has a default namespace (`ckad-deploy`); `ckad-a` does not.
- **Namespaces.** Each question names its Namespace. Use exactly that one.
- **Files.** Files a question starts from, and answers that are files, are under
  `/tmp/kbook/ckad/<question>/`. Write exactly the file the question names.
- **Tools.** `docker` (question 1) and `helm` (question 7) are on your path, as in
  Chapters 14 and 16. Podman works for question 1 too.
- **Documentation.** Allowed: `kubectl explain`, `--help`, and the documentation
  Chapter 38 lists (kubernetes.io/docs, kubernetes.io/blog, helm.sh/docs). Not
  allowed: this book's chapters and the solutions file, until you have scored.
- **Weights.** Every question has a task weight. A question counts only when
  everything it asks for is right; then you earn its whole weight. Your score is
  the sum.
- **Time.** `make mock-score` shows the time used. It never stops you.

When you are done, run `make mock-score EXAM=ckad`, then read
[`lab/solutions.md`](lab/solutions.md) for every question you missed.

> **Exam tip:** Six minutes per question. If a question is not going well after
> ten, note its number and move on; come back at the end.

---

## Question 1 | Rebuild an image

Task weight: 6%

Use context: `kubectl config use-context ckad-a`

The directory `/tmp/kbook/ckad/1/app` holds a Dockerfile and its script. Change
the Dockerfile so that the image sets the environment variable `APP_VERSION` to
`2.0`. Build the image with the tag `ckad-web:2.0`, and save it in the Docker
archive format to `/tmp/kbook/ckad/1/ckad-web.tar`.

---

## Question 2 | A sidecar that ships a log

Task weight: 6%

Use context: `kubectl config use-context ckad-a`

The manifest `/tmp/kbook/ckad/2/logger.yaml` describes a Pod `logger` in Namespace
`ckad-design` whose container `app` appends lines to `/var/log/app/app.log`. Add a
native sidecar container named `shipper`, image `busybox:1.36`, that runs
`tail -F /var/log/app/app.log` from the same volume, so that the app's lines appear
in the logs of `shipper`. Create the Pod. It must be Running with every container
ready.

---

## Question 3 | An agent on every node

Task weight: 4%

Use context: `kubectl config use-context ckad-a`

In Namespace `ckad-design`, create a DaemonSet `node-agent` running `busybox:1.36`
with the command `sleep 3600`. It must run one ready Pod on every node of the
cluster, including the control plane node.

---

## Question 4 | Scratch space in memory

Task weight: 4%

Use context: `kubectl config use-context ckad-a`

In Namespace `ckad-design`, create a Pod `scratch` running `busybox:1.36` with the
command `sleep 3600`. Give it a volume named `scratch` that lives in memory and is
limited to `64Mi`, mounted at `/scratch`. The Pod must be Running.

---

## Question 5 | A careful rolling update

Task weight: 5%

Use context: `kubectl config use-context ckad-b`

In Namespace `ckad-deploy`, the Deployment `frontend` runs 4 replicas of
`nginx:1.26`. Change its update strategy to a rolling update that adds at most one
extra Pod and never has fewer than 4 available (`maxSurge` 1, `maxUnavailable` 0).
Then update it to `nginx:1.27`. All 4 replicas must be updated and available, with
no old Pods left.

---

## Question 6 | A canary

Task weight: 6%

Use context: `kubectl config use-context ckad-b`

In Namespace `ckad-deploy`, the Deployment `checkout` runs 4 Pods of `nginx:1.26`
labeled `app=checkout` and `track=stable`, behind the Service `checkout`. Release
`nginx:1.27` as a canary: create a Deployment `checkout-canary` with 1 replica whose
Pods are labeled `app=checkout` and `track=canary`, so that the Service sends about
one request in five to it. Do not change the Deployment `checkout` or the Service.
The Service must have 5 ready endpoints.

---

## Question 7 | Upgrade a Helm release

Task weight: 5%

Use context: `kubectl config use-context ckad-b`

In Namespace `ckad-deploy`, the Helm release `cache` was installed from the chart in
`/tmp/kbook/ckad/7/chart` with the value `greeting=hello-ckad`. Upgrade the release
so that it runs image tag `1.27` with `3` replicas (the chart's values `image.tag`
and `replicaCount`). The value `greeting` must still be `hello-ckad`. The release
must be `deployed`, and its 3 Pods ready.

---

## Question 8 | A Kustomize overlay

Task weight: 5%

Use context: `kubectl config use-context ckad-b`

`/tmp/kbook/ckad/8/base` is a Kustomize base with a Deployment `ledger`. Create the
overlay `/tmp/kbook/ckad/8/overlays/prod/kustomization.yaml` that uses the base and
sets the Namespace `ckad-deploy`, 2 replicas, and the label `env=prod` on the
Deployment and its Pod template. Apply the overlay. The Deployment must have 2
ready replicas.

---

## Question 9 | A removed API version

Task weight: 3%

Use context: `kubectl config use-context ckad-a`

The manifest `/tmp/kbook/ckad/9/cleanup.yaml` no longer applies: the cluster does
not serve its API version. Change the file to the API version the cluster serves
for CronJobs, and create the CronJob from it.

---

## Question 10 | Probes

Task weight: 4%

Use context: `kubectl config use-context ckad-a`

In Namespace `ckad-ops`, add two probes to the container of the Deployment `api`:

- A readiness probe: HTTP GET on path `/`, port `80`, every 5 seconds.
- A liveness probe: TCP on port `80`, first after 10 seconds, then every 20 seconds.

The rollout must finish with 2 ready replicas.

---

## Question 11 | Errors from one container

Task weight: 3%

Use context: `kubectl config use-context ckad-a`

In Namespace `ckad-ops`, the Pod `batch-runner` has two containers. Save every line
that the container `worker` printed and that contains `ERROR`, in order and with no
other text, to `/tmp/kbook/ckad/11/errors.txt`.

---

## Question 12 | A Deployment that keeps crashing

Task weight: 5%

Use context: `kubectl config use-context ckad-a`

In Namespace `ckad-ops`, the Deployment `reports` never becomes ready. Find out why
and fix it, without changing the container's command. The Deployment must have 1
ready replica, and no old Pods left.

---

## Question 13 | Configuration and credentials as files

Task weight: 6%

Use context: `kubectl config use-context ckad-a`

In Namespace `ckad-sec`:

- Create a ConfigMap `db-config` from the file `/tmp/kbook/ckad/13/db.properties`,
  so that the key is the file name.
- Create a Secret `db-cred` with the keys `username` (value `app`) and `password`
  (value `s3cr3t`).
- Create a Pod `db-client` running `busybox:1.36` with the command `sleep 3600`
  that mounts the ConfigMap at `/etc/db-config` and the Secret at `/etc/db-cred`.
  The Pod must be Running.

---

## Question 14 | A hardened Pod

Task weight: 6%

Use context: `kubectl config use-context ckad-a`

In Namespace `ckad-sec`, create a Pod `hardened` with one container `hardened`
running `busybox:1.36` with the command `sleep 3600`. It must:

- run as user `1000` and group `3000`, with `runAsNonRoot` set to `true`;
- not allow privilege escalation;
- have a read-only root file system;
- drop all capabilities.

The Pod must be Running.

---

## Question 15 | Permissions for a ServiceAccount

Task weight: 6%

Use context: `kubectl config use-context ckad-a`

In Namespace `ckad-sec`, create a ServiceAccount `deployer`. Create a Role
`deploy-editor` that allows `get`, `list`, `create`, `update`, and `patch` on
Deployments and nothing else, and bind it to `deployer` with a RoleBinding
`deployer-binding`. Then create a Deployment `ci` (image `nginx:1.27`, 1 replica)
whose Pods run as `deployer`. It must have 1 ready replica.

---

## Question 16 | Requests and limits under a quota

Task weight: 4%

Use context: `kubectl config use-context ckad-a`

In Namespace `ckad-quota`, the Deployment `burst` should run 3 Pods, but none
start. Give its container requests of `100m` CPU and `64Mi` memory, and limits of
`200m` CPU and `128Mi` memory, so that all 3 Pods run. Do not change the
ResourceQuota `compute`.

---

## Question 17 | A custom resource

Task weight: 3%

Use context: `kubectl config use-context ckad-a`

The cluster has a custom resource for caches. Find it, and create a cache named
`session-cache` in Namespace `ckad-sec` with the size `medium` and `3` replicas.

---

## Question 18 | A Service that reaches nothing

Task weight: 6%

Use context: `kubectl config use-context ckad-a`

In Namespace `ckad-net`, the Pod `probe` cannot reach the Service `catalog`
(`wget -qO- http://catalog` fails), although the Deployment `catalog` runs. Fix the
Service so that `probe` gets the nginx welcome page from it. Do not change the
Deployment.

---

## Question 19 | Protect the database

Task weight: 7%

Use context: `kubectl config use-context ckad-a`

In Namespace `ckad-net`, the Pod `db` (label `app=db`) serves on port 80 behind the
Service `db`. Create a NetworkPolicy `db-access` so that only Pods labeled
`app=api` can connect to `db`, and only on TCP port 80. Other traffic in the
Namespace must not change: for example, `web` must still reach the Service `shop`.

---

## Question 20 | A Service and an Ingress

Task weight: 6%

Use context: `kubectl config use-context ckad-a`

In Namespace `ckad-net`:

- Expose the Deployment `cart` as a ClusterIP Service `cart` on port `8080`,
  forwarding to the container's port `80`.
- Create an Ingress `store` with ingress class `nginx` and host
  `store.ckad.example.test`, that sends the path `/shop` to the Service `shop` on
  port `80`, and the path `/cart` to the Service `cart` on port `8080`. Both paths
  use the path type `Prefix`.
