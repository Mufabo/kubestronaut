# Chapter 38: Navigating the allowed documentation

> **Exams:** CKAD · CKA · CKS
> **Difficulty:** Beginner
> **Time:** ~30 min reading, ~45 min exploration exercise
> **Lab tier:** none (a browser; a cluster helps for the last part of the exercise)
> **Prerequisites:** Chapter 03 (kubectl fluency), Chapter 37 (terminal speed)

## Learning objectives

After this chapter you can:

- Say which documentation sites each performance-based exam allows, and what the rules around them are
- Find your way around kubernetes.io/docs by its four sections, and know which one answers which kind of question
- Reach the pages that the common exam tasks need in a few clicks or one search, without leaving the allowed sites
- Copy a manifest from the documentation safely, and check it before you rely on it
- Choose between the documentation and `kubectl explain`, `--help`, or `--dry-run` for a given question

## Concepts

The CKAD, CKA, and CKS are open-book in a narrow sense: a browser inside the exam
environment may open a short list of documentation sites, and nothing else. That
is a real advantage, but only for someone who already knows where things are.
Two hours for 15 to 20 tasks leaves no time to learn the site during the exam.
This chapter is about building that map in advance.

The KCNA and KCSA are different: multiple-choice exams with no documentation at
all. This chapter is for the three performance-based exams.

### What each exam allows

The Linux Foundation publishes the list of allowed resources, and it changes from
time to time. Read the current page before your exam. When this chapter was
written (October 2026), it said:

| Exam | Allowed sites |
| --- | --- |
| CKAD | `kubernetes.io/docs`, `kubernetes.io/blog`, `helm.sh/docs` |
| CKA | the same, plus the Gateway API documentation at `gateway-api.sigs.k8s.io` |
| CKS | `kubernetes.io/docs`, `kubernetes.io/blog`, and the documentation of the security tools the exam uses: Falco, bom, etcd, the NGINX Ingress controller, Cilium, and Istio |

Three rules come with the list:

- **Use the browser inside the exam environment.** Nothing on your own computer is available.
- **You may use the search on the allowed sites, but you must not open results that lead elsewhere.** A search inside the Kubernetes docs that suggests a third-party page is not an invitation to open it.
- **Translations of the docs are allowed**, but the English pages are the most up to date.

Some tasks also come with a **Quick Reference** box that links documentation for
that task. Those links are allowed too.

### The four sections of kubernetes.io/docs

The Kubernetes documentation is organized by the kind of question it answers. Once
you know that, most searches become unnecessary:

| Section | Answers | Exam use |
| --- | --- | --- |
| **Concepts** (`/docs/concepts/`) | What is it, and how does it behave? | Field meanings, rules (for example, how NetworkPolicies combine), and complete example manifests |
| **Tasks** (`/docs/tasks/`) | How do I do this, step by step? | Procedures with commands and manifests: probes, security contexts, ConfigMaps, kubeadm upgrades, etcd backups |
| **Reference** (`/docs/reference/`) | What exactly is the syntax? | The kubectl quick reference, JSONPath, every API kind's fields, and the RBAC reference |
| **Setup** (`/docs/setup/`) | How do I build a cluster? | Installing kubeadm and creating a cluster with it |

The **Tutorials** section teaches end-to-end examples. It is useful for learning,
and rarely the fastest place during an exam.

### Pages worth knowing by heart

Most exam tasks map onto a small set of pages. Visit each of these before your exam
and note where on the page the manifest or command you need sits:

| Task | Page |
| --- | --- |
| Any kubectl syntax, JSONPath | `/docs/reference/kubectl/quick-reference/`, `/docs/reference/kubectl/jsonpath/` |
| Probes | `/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/` |
| `securityContext`, capabilities | `/docs/tasks/configure-pod-container/security-context/` |
| ConfigMaps in Pods, Secrets | `/docs/tasks/configure-pod-container/configure-pod-configmap/`, `/docs/concepts/configuration/secret/` |
| Jobs, CronJobs | `/docs/concepts/workloads/controllers/job/`, `/docs/concepts/workloads/controllers/cron-jobs/` |
| NetworkPolicy | `/docs/concepts/services-networking/network-policies/` |
| Ingress, Gateway API | `/docs/concepts/services-networking/ingress/`, `/docs/concepts/services-networking/gateway/` |
| PV, PVC, StorageClass | `/docs/concepts/storage/persistent-volumes/` |
| Taints, affinity, nodeSelector | `/docs/concepts/scheduling-eviction/taint-and-toleration/`, `/docs/concepts/scheduling-eviction/assign-pod-node/` |
| Static Pods | `/docs/tasks/configure-pod-container/static-pod/` |
| Quotas, LimitRanges | `/docs/concepts/policy/resource-quotas/`, `/docs/concepts/policy/limit-range/` |
| HPA | `/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/` |
| RBAC | `/docs/reference/access-authn-authz/rbac/` |
| Pod Security Standards | `/docs/concepts/security/pod-security-standards/` |
| kubeadm install, create, upgrade | `/docs/setup/production-environment/tools/kubeadm/install-kubeadm/`, `.../create-cluster-kubeadm/`, `/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/` |
| Certificates with kubeadm | `/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/` |
| etcd backup and restore | `/docs/tasks/administer-cluster/configure-upgrade-etcd/` |
| `crictl` | `/docs/tasks/debug/debug-cluster/crictl/` |
| Helm commands | `helm.sh/docs/`, for example `helm.sh/docs/helm/helm_install/` |
| HTTPRoute fields (CKA) | `gateway-api.sigs.k8s.io/reference/api-types/httproute/` |

### Searching well

The search box on kubernetes.io searches the documentation. Search for the **kind
or the field name**, not for the task: "NetworkPolicy", "persistentVolumeReclaimPolicy",
or "startupProbe" lands on the right page; "how do I block traffic" does not. On a
long page, the browser's find (`Ctrl+F`) is faster than scrolling: search for the
field you need, such as `podSelector` or `--data-dir`.

The docs also show the version they describe. The site shows the current
Kubernetes release by default, which is what the exams run; older versions live on
their own subdomains, and you have no reason to use them.

### The documentation is not the only reference

Three answers live in the terminal, and they are often faster than any page:

- **`kubectl explain`** prints the schema of any field for the cluster's own version: `kubectl explain pod.spec.containers.securityContext`. Add `--recursive` to see the whole tree.
- **`--help`** on every command shows its flags and examples: `kubectl create cronjob --help` shows the exact syntax, including how to pass the command.
- **`--dry-run=client -o yaml`** writes a manifest skeleton you can edit, so you rarely need to copy a whole manifest from a page.

Use the docs for what these cannot give you: rules and behavior (Concepts),
multi-step procedures (Tasks: kubeadm, etcd), and kinds `kubectl create` cannot
generate (a NetworkPolicy, a PersistentVolume, a StatefulSet).

### Copying a manifest safely

Copying from the documentation is allowed and normal. Three things go wrong often:

- **Indentation.** The exam terminal's editor may re-indent pasted YAML. Paste into an empty file, then check it: `kubectl apply --dry-run=server -f file.yaml` lets the API server validate it without storing anything.
- **Names and Namespaces.** The example's names (`my-pod`, `default`) must become the task's. Change every occurrence, including selectors and labels that must match.
- **Extra fields.** Examples show many options. Remove what the task did not ask for, because a check may require exactly what the task states.

## Exploration exercise

You need a browser, and a cluster for the last step. Time yourself: the target is
under a minute for each lookup.

1. Starting from `kubernetes.io/docs`, without the search box, find the page with a NetworkPolicy that allows ingress only from Pods with a given label. Note the path you clicked through.
2. With the search box, find the field that sets how long a Job may run in total. Note its name and the page it is on.
3. On the kubectl quick reference, find how to list Pods sorted by restart count. Write the command.
4. Find the etcd backup and restore procedure. Note the three certificate flags it uses with `etcdctl`.
5. On `helm.sh/docs`, find how to install a chart at a specific version into a new Namespace. Write the flags.
6. On the Gateway API site, find the HTTPRoute field that sends a share of traffic to a second backend (CKA readers).
7. In a cluster, answer question 2 again with `kubectl explain` instead of the browser, and compare the time it took.

There are no automated checks for this exercise. The answers are in the questions
at the end of the chapter.

## Exam tips

> **Exam tip:** Read the allowed-resources page in the week before your exam, not months before. The list changes, and so does the exam's Kubernetes version.
>
> **Exam tip:** Prefer `kubectl explain` and `--help` for syntax, and the docs for procedures and rules. Switching to the browser costs time each way.
>
> **Exam tip:** Search the docs for kinds and field names, and use `Ctrl+F` on long pages. A search phrased as a question returns long Concepts pages you then have to read.
>
> **Exam tip:** After pasting YAML from the docs, run `kubectl apply --dry-run=server -f FILE` before the real apply. It catches indentation and field errors without creating anything.

## Common misconceptions

- "The exams are closed-book." The CKAD, CKA, and CKS allow a specific list of documentation sites; the KCNA and KCSA allow nothing.
- "Any Kubernetes-related site is allowed." Only the listed sites are; a search result that leads elsewhere must not be opened.
- "The docs are the fastest way to check a field." `kubectl explain` answers in the terminal, for the cluster's own version.
- "A manifest copied from the docs is ready to use." It needs the task's names, Namespace, and only the fields the task asks for.
- "Older docs versions are safer." The exams run a current release, and the site's default version matches it.

<!-- QUESTIONS:START -->

## End-of-chapter questions

**1.** `CKAD` `CKA` `CKS` Which documentation may you open during the CKA exam?

- **A.** Any site, as long as you do not ask anyone for help
- **B.** The Kubernetes docs and blog, the Helm docs, and the Gateway API docs
- **C.** Nothing; the CKA is closed-book
- **D.** The Kubernetes docs and any blog post they link to

**2.** `CKAD` `CKA` `CKS` During the exam, a search on kubernetes.io suggests a page on a third-party blog. What do you do?

- **A.** Open it, because the search was on an allowed site
- **B.** Do not open it; only results on the allowed sites may be opened
- **C.** Open it in a new tab, which is not monitored
- **D.** Copy its URL into the terminal and read it with curl

**3.** `KCNA` Which documentation may you use during the KCNA exam?

- **A.** The Kubernetes docs only
- **B.** None: the KCNA is a multiple-choice exam without documentation
- **C.** The CNCF landscape and the Kubernetes docs
- **D.** Anything on kubernetes.io

**4.** `CKAD` `CKA` Which section of kubernetes.io/docs gives step-by-step procedures, such as upgrading a kubeadm cluster or backing up etcd?

- **A.** Concepts
- **B.** Tasks
- **C.** Reference
- **D.** Tutorials

**5.** `CKAD` `CKA` Where do you find kubectl's output options and a JSONPath example quickly?

- **A.** In the Concepts section, under Overview
- **B.** In the Reference section: the kubectl quick reference and the JSONPath page
- **C.** In the Kubernetes blog
- **D.** Only in `kubectl --help`

**6.** `CKAD` `CKA` You need the exact name and type of a field in a Pod's `securityContext`. What is usually fastest?

- **A.** `kubectl explain pod.spec.securityContext`
- **B.** Searching the docs for "how to secure a pod"
- **C.** The Kubernetes blog
- **D.** Reading the Pod Security Standards page from the top

**7.** `CKAD` `CKA` `CKS` Which search on kubernetes.io is most likely to land on the right page?

- **A.** how do I stop pods from talking to each other
- **B.** NetworkPolicy
- **C.** kubernetes security best practices
- **D.** pod traffic problem

**8.** `CKAD` `CKA` You pasted a NetworkPolicy from the docs into a file. How do you check it before it takes effect?

- **A.** `kubectl apply --dry-run=server -f policy.yaml`
- **B.** `kubectl create -f policy.yaml --validate=false`
- **C.** Open it in the browser
- **D.** There is no way; apply it and test

**9.** `CKAD` `CKA` A manifest copied from the docs works, but the task's check fails. What is the most likely cause?

- **A.** The docs use an outdated API
- **B.** It still carries the example's names, labels, or extra fields that the task did not ask for
- **C.** Copied YAML is never accepted
- **D.** The exam blocks manifests from the docs

**10.** `CKA` Which site describes the fields of an HTTPRoute in full?

- **A.** helm.sh/docs
- **B.** gateway-api.sigs.k8s.io, under the API reference
- **C.** kubernetes.io/blog only
- **D.** None of the allowed sites

**11. (Task)** `CKAD` `CKA` Using only `kubectl`, find the field that limits how long a Job may run in total, and its type.

**12. (Task)** `CKA` Without the browser, show the flags that `etcdctl snapshot save` needs to reach a kubeadm cluster's etcd, and where on the control plane node their values come from.

<details>
<summary>Answers</summary>

**1. B.** The Linux Foundation's list for the CKA (as of October 2026) is kubernetes.io/docs, kubernetes.io/blog, helm.sh/docs, and gateway-api.sigs.k8s.io, plus links in a task's Quick Reference box. The list changes, so read it before the exam.

**2. B.** The rules allow searching the Kubernetes documentation, but not opening external results. Everything you open must be on the allowed list.

**3. B.** The KCNA and KCSA are online, proctored, multiple-choice exams. The documentation rules in this chapter apply to the performance-based CKAD, CKA, and CKS.

**4. B.** Tasks are procedures with commands and manifests. Concepts explain behavior, Reference holds exact syntax (kubectl, API fields, RBAC), and Tutorials walk through longer learning examples.

**5. B.** `/docs/reference/kubectl/quick-reference/` collects common commands, and `/docs/reference/kubectl/jsonpath/` explains the syntax with examples. `kubectl get --help` lists the output formats too.

**6. A.** `kubectl explain` prints the schema for the cluster's own version, in the terminal you are already using. Use the docs for rules and procedures, which `explain` does not give.

**7. B.** Searching for the kind or a field name finds the page that defines it. Questions in plain language return long overview pages.

**8. A.** A server-side dry run sends the object to the API server, which validates and defaults it as for a real request, but stores nothing. Indentation and field errors show up immediately.

**9. B.** Examples show names like my-pod, the default Namespace, and optional fields. Replace every name and label with the task's, and remove what the task did not state.

**10. B.** The Gateway API project documents its kinds at gateway-api.sigs.k8s.io (for example /reference/api-types/httproute/), which the CKA allows. kubernetes.io/docs explains the concepts on /docs/concepts/services-networking/gateway/.

**11.**

```bash
kubectl explain job.spec | grep -i -A3 deadline
kubectl explain job.spec.activeDeadlineSeconds
```

The field is `spec.activeDeadlineSeconds`, an integer number of seconds. The Jobs page (`/docs/concepts/workloads/controllers/job/`) explains how it interacts with `backoffLimit`, which `explain` does not.

**12.**

```bash
etcdctl --help | grep -E -- '--(endpoints|cacert|cert|key)'
sudo grep -E -- '--(listen-client-urls|trusted-ca-file|cert-file|key-file)' /etc/kubernetes/manifests/etcd.yaml
```

`--endpoints`, `--cacert`, `--cert`, and `--key`; their values are the etcd manifest's client URL, trusted CA, certificate, and key (Chapter 20). The docs page *Operating etcd clusters for Kubernetes* shows the same procedure.

</details>

<!-- QUESTIONS:END -->

## Further reading

- The Linux Foundation's *Resources allowed during exam* page and its CKA/CKAD and CKS instructions (re-read them before you book)
- `kubernetes.io/docs/home/`: the start page, with the four sections
- Chapter 37: terminal speed, which saves more time than any bookmark
- Chapter 39 next: exam logistics and a study plan per certification
