# Mock exam: KCNA practice exam, set 2

> **Exam:** KCNA
> **Format:** 60 multiple-choice questions, 90 minutes, pass mark 75%
> **Covers:** the four KCNA domains, weighted as in the curriculum: Kubernetes Fundamentals 44% (26 questions), Container Orchestration 28% (17), Cloud Native Application Delivery 16% (10), Cloud Native Architecture 12% (7)
> **Lab tier:** none (no cluster needed)
> **Prerequisites:** the KCNA study plan in Chapter 39, and set 1 (`mock-exams/kcna`)

A second, independent set of 60 questions, none of them repeated from set 1. Take
set 1 first; when you retake an exam you remember its answers, so a fresh set is
the honest measure of whether you are ready. It runs the same way:

```bash
make quiz EXAM=kcna2          # start, or resume, an attempt; the clock starts with the first question
make quiz-reset EXAM=kcna2    # throw the attempt away and start over
```

Each attempt shows the questions in a new order. Answer with a letter; you can go
back and forth, flag questions, and see a review of what is answered and flagged.
Your answers are saved after every step, so you can close the terminal and resume,
but the clock keeps running, as in the real exam. When you submit, or when the 90
minutes are up, you get your score per domain, and the explanation of every
question you missed.

The questions are original and written from the public curriculum only; they are
not real exam questions. They are also listed below, in curriculum order, with
the answers hidden at the end. Use the list to review after an attempt, not to
take the exam: reading them in order gives away the domain of each question.

<!-- QUESTIONS:START -->

## Questions

**1.** Which control plane component runs the loops that make the cluster's actual state match the desired state for Deployments, ReplicaSets, and Nodes?

- **A.** kube-scheduler
- **B.** kube-controller-manager
- **C.** kube-proxy
- **D.** etcd

**2.** What does the cloud-controller-manager do?

- **A.** It schedules Pods onto cloud instances
- **B.** It stores the cluster's state in the cloud
- **C.** It runs the controllers that talk to a cloud provider's API, such as creating load balancers and labeling nodes with their zone
- **D.** It replaces the kubelet on cloud nodes

**3.** Why can a cluster run several kube-apiserver instances at the same time?

- **A.** Each instance owns a separate part of etcd
- **B.** Only one instance is active; the others wait for a leader election
- **C.** Each instance serves different Namespaces
- **D.** The API server keeps no state of its own; every instance reads and writes the same etcd

**4.** In the API version apps/v1, what are apps and v1?

- **A.** The API group and its version
- **B.** The Namespace and the resource version
- **C.** The kind and its revision
- **D.** The cluster name and the Kubernetes version

**5.** A Pod's container exits with code 0, and its restartPolicy is OnFailure. What happens?

- **A.** The container is restarted
- **B.** The container is not restarted, and the Pod ends as Succeeded
- **C.** The Pod is deleted
- **D.** The kubelet restarts the whole node

**6.** A Pod has two init containers and one app container. In which order do they run?

- **A.** All three at the same time
- **B.** The app container first, then the init containers
- **C.** The first init container to completion, then the second, then the app container
- **D.** In random order

**7.** A container requests 250m of CPU. How much is that?

- **A.** 250 MiB of memory
- **B.** 250 CPU cores
- **C.** 250 milliseconds per minute
- **D.** A quarter of one CPU core

**8.** Every container in a Pod sets CPU and memory limits equal to its requests. Which QoS class does the Pod get?

- **A.** Guaranteed
- **B.** Burstable
- **C.** BestEffort
- **D.** Critical

**9.** What do the Pods of a StatefulSet usually get through a headless Service?

- **A.** One shared virtual IP for all replicas
- **B.** A stable DNS name per Pod, such as db-0.db.prod.svc.cluster.local
- **C.** A public IP per Pod
- **D.** No DNS names at all

**10.** A Job has completions: 6 and parallelism: 2. How does it run?

- **A.** Six Pods at once
- **B.** Two Pods, each running six times
- **C.** Up to two Pods at a time, until six have completed successfully
- **D.** Six Pods, two of which may fail

**11.** What does a selector such as environment in (prod, staging) match?

- **A.** Objects whose name contains prod or staging
- **B.** Objects in the Namespaces prod and staging
- **C.** Objects annotated with environment
- **D.** Objects whose label environment has the value prod or staging

**12.** You delete a Deployment with the default settings. What happens to its ReplicaSets and Pods?

- **A.** The garbage collector deletes them too, because they are owned by the Deployment
- **B.** They keep running without an owner
- **C.** Only the Pods are deleted; the ReplicaSets remain
- **D.** They move to the default Namespace

**13.** Which statement about labels and annotations is true?

- **A.** Both can be used in selectors
- **B.** Labels identify and select objects; annotations hold other metadata for tools and people
- **C.** Annotations are limited to 63 characters, labels are not
- **D.** Labels are only allowed on Pods

**14.** Which kubectl command shows a Pod's node and IP address in its output?

- **A.** kubectl get pods --show-labels
- **B.** kubectl get pods -o name
- **C.** kubectl get pods -o wide
- **D.** kubectl top pods

**15.** Why do etcd clusters run with three or five members, not four?

- **A.** etcd only supports odd numbers
- **B.** Four members are slower to start
- **C.** Four members need a separate leader node
- **D.** Four members tolerate only one failure, like three, while needing one more machine

**16.** Which tool creates and upgrades a Kubernetes cluster on machines you provide, and is the reference installer of the project?

- **A.** kubeadm
- **B.** kubectl
- **C.** Helm
- **D.** kubelet

**17.** What is a static Pod?

- **A.** A Pod that never restarts
- **B.** A Pod that the kubelet runs directly from a manifest file on its node, without the scheduler
- **C.** A Pod with a fixed IP address
- **D.** A Pod created by a DaemonSet

**18.** A Pod has preferredDuringSchedulingIgnoredDuringExecution node affinity for zone=a, and no node in zone a has room. What happens?

- **A.** The Pod stays Pending until a node in zone a has room
- **B.** The Pod is rejected
- **C.** The scheduler places it on another node that fits; the preference only adds to a node's score
- **D.** The scheduler evicts Pods from zone a

**19.** What do topology spread constraints do?

- **A.** They limit how much CPU a Pod may use
- **B.** They copy Pods to every zone
- **C.** They connect clusters in different regions
- **D.** They spread a workload's Pods evenly across zones, nodes, or other topology domains

**20.** A high-priority Pod cannot be scheduled because the nodes are full. What can the scheduler do?

- **A.** Preempt (evict) lower-priority Pods to make room for it
- **B.** Add a node to the cluster
- **C.** Lower the Pod's requests
- **D.** Nothing; priority only affects the queue order

**21.** A Node is NotReady for several minutes. What happens to the Pods of a Deployment that ran on it?

- **A.** Nothing, ever
- **B.** After the toleration period for the not-ready or unreachable taint, they are evicted, and the ReplicaSet creates replacements on other nodes
- **C.** They move to the node with their memory intact
- **D.** The Deployment is deleted

**22.** What does a multi-stage container image build achieve?

- **A.** It runs several containers in one image
- **B.** It builds the image on several machines in parallel
- **C.** It builds in one stage with the full toolchain and copies only the result into a small final image
- **D.** It signs the image

**23.** What is runc?

- **A.** A Kubernetes controller
- **B.** A container registry
- **C.** A high-level runtime that pulls images and implements the CRI
- **D.** A low-level OCI runtime that creates the container process with namespaces and cgroups

**24.** Where does a node get the images its Pods use?

- **A.** From a container registry, such as Docker Hub or a private registry, pulled by the container runtime
- **B.** From etcd
- **C.** From the API server
- **D.** From the control plane node's disk

**25.** What does imagePullPolicy: IfNotPresent do?

- **A.** Always pulls the image, even if it is cached
- **B.** Pulls the image only if it is not already on the node
- **C.** Never pulls; the image must be on the node
- **D.** Pulls only images tagged latest

**26.** Why should a container image not contain configuration that differs between environments?

- **A.** Images cannot contain files
- **B.** Configuration files make images too large to pull
- **C.** One immutable image should run everywhere; ConfigMaps, Secrets, and environment variables supply what differs
- **D.** Kubernetes refuses images with configuration files

**27.** What is a headless Service?

- **A.** A Service without a selector
- **B.** A Service of type ExternalName
- **C.** A Service in a Namespace without Pods
- **D.** A Service with clusterIP: None, whose DNS name returns the IPs of its Pods directly

**28.** Which objects record the actual Pod addresses behind a Service?

- **A.** EndpointSlices
- **B.** ConfigMaps
- **C.** NetworkPolicies
- **D.** Nodes

**29.** Which statement compares the Gateway API with Ingress correctly?

- **A.** The Gateway API replaces Services
- **B.** The Gateway API splits roles into GatewayClass, Gateway, and routes such as HTTPRoute, and supports more protocols and traffic splitting than Ingress
- **C.** Ingress is newer than the Gateway API
- **D.** The Gateway API works without any controller

**30.** A Pod in Namespace shop looks up the name db. Which Service does it reach?

- **A.** The Service db in Namespace default
- **B.** Any Service named db in the cluster, at random
- **C.** The Service db in its own Namespace, shop, through the DNS search path
- **D.** None; a short name never resolves

**31.** Which component answers DNS queries for Services inside a cluster?

- **A.** kube-proxy
- **B.** The API server
- **C.** etcd
- **D.** CoreDNS

**32.** Which modes can kube-proxy use to implement Services on Linux nodes?

- **A.** iptables, IPVS, and nftables
- **B.** TCP and UDP
- **C.** DNS and HTTP
- **D.** Overlay and underlay

**33.** A NetworkPolicy's ingress rule has from: [namespaceSelector: {matchLabels: {team: a}}]. Which Pods may connect?

- **A.** Pods labeled team=a in any Namespace
- **B.** All Pods in Namespaces labeled team=a
- **C.** Only Pods in the policy's own Namespace
- **D.** No Pods; namespaceSelector only works for egress

**34.** A RoleBinding in Namespace dev refers to a ClusterRole. Where do the permissions apply?

- **A.** In every Namespace
- **B.** Nowhere; a RoleBinding cannot refer to a ClusterRole
- **C.** Only in Namespace dev
- **D.** Only on cluster-scoped resources

**35.** What does a validating admission controller do?

- **A.** It authenticates users
- **B.** It schedules Pods
- **C.** It encrypts objects before storing them
- **D.** It inspects a request after authorization and can reject it before the object is stored

**36.** Which security setting prevents a process in a container from gaining more privileges than its parent, for example through setuid binaries?

- **A.** allowPrivilegeEscalation: false
- **B.** hostNetwork: false
- **C.** imagePullPolicy: Always
- **D.** terminationGracePeriodSeconds: 0

**37.** What is the Container Storage Interface (CSI)?

- **A.** A format for container images
- **B.** A standard interface through which storage vendors provide volume drivers to Kubernetes outside its own code
- **C.** A backup tool
- **D.** The kubelet's API for logs

**38.** A StorageClass has reclaimPolicy: Delete. What happens when a claim that was dynamically provisioned from it is deleted?

- **A.** The volume is kept for manual reuse
- **B.** The data is moved to a backup
- **C.** The PersistentVolume and the underlying storage are deleted
- **D.** The claim cannot be deleted

**39.** Which access mode lets many nodes mount the same volume read-write at once?

- **A.** ReadWriteOnce
- **B.** ReadOnlyMany
- **C.** ReadWriteOncePod
- **D.** ReadWriteMany

**40.** A PersistentVolumeClaim stays Pending. Which cause is most likely?

- **A.** No PersistentVolume matches it, and no StorageClass can provision one (or it waits for a Pod with WaitForFirstConsumer)
- **B.** The Pod using it is CrashLoopBackOff
- **C.** The Namespace has no Service
- **D.** kube-proxy is down

**41.** A container's last state shows reason OOMKilled and exit code 137. What happened?

- **A.** The image could not be pulled
- **B.** The container exceeded its memory limit and the kernel killed it
- **C.** The liveness probe failed
- **D.** The node was drained

**42.** A node shows NotReady. Where do you look first?

- **A.** The application logs of a Pod on another node
- **B.** The Ingress controller
- **C.** The node's conditions in kubectl describe node, then the kubelet and container runtime on the node
- **D.** The Helm releases

**43.** Pod Security Admission is configured how?

- **A.** With a cluster-wide webhook that you must install
- **B.** With a ConfigMap per Pod
- **C.** Only through the API server's flags
- **D.** With labels on each Namespace that choose a Pod Security Standard and a mode (enforce, audit, warn)

**44.** What does helm rollback do?

- **A.** Returns a release to an earlier revision of its manifests and values
- **B.** Deletes the release
- **C.** Downgrades Helm itself
- **D.** Rolls back the cluster's Kubernetes version

**45.** Which statement about Argo CD and Flux is true?

- **A.** Both are container runtimes
- **B.** Both are GitOps tools: controllers in the cluster that keep it in sync with what is declared in Git
- **C.** Argo CD builds images and Flux runs tests
- **D.** Both replace kubectl entirely

**46.** What does a Helm values file do?

- **A.** It lists the chart's dependencies
- **B.** It stores the release history
- **C.** It sets parameters that the chart's templates use, overriding the chart's defaults
- **D.** It defines the chart's name and version

**47.** In a typical CI/CD pipeline for Kubernetes, what is usually the result of the CI part?

- **A.** A running cluster
- **B.** A new Namespace
- **C.** A Helm repository
- **D.** A tested container image pushed to a registry, with a version tag or digest

**48.** Why should a deployment pipeline refer to images by digest or by a unique tag, not by latest?

- **A.** So that every environment runs exactly the image that was tested, and a rollback returns to a known image
- **B.** Because latest is not allowed in Kubernetes
- **C.** Because digests pull faster
- **D.** Because tags are case-sensitive

**49.** What does revisionHistoryLimit on a Deployment control?

- **A.** How often the Deployment may be updated
- **B.** How many old ReplicaSets are kept, which is how far back a rollback can go
- **C.** How many Pods may be unavailable during an update
- **D.** How long a rollout may take

**50.** How do you follow a Pod's logs live, as new lines are written?

- **A.** kubectl logs POD --previous
- **B.** kubectl describe pod POD
- **C.** kubectl logs -f POD
- **D.** kubectl get pod POD -w

**51.** Where do you find the reasons Kubernetes gives for scheduling failures, image pulls, and probe failures of a Pod?

- **A.** In the container's logs
- **B.** In the Pod's labels
- **C.** In etcd's logs
- **D.** In the Pod's events, shown by kubectl describe pod or kubectl get events

**52.** What does kubectl debug node/NAME -it --image=busybox:1.36 give you?

- **A.** A shell in a Pod on that node with the node's file system mounted at /host
- **B.** SSH access to the node
- **C.** A copy of the node in a new VM
- **D.** The kubelet's logs

**53.** A Deployment's rollout of a new image hangs: new Pods never become ready. What does kubectl rollout status report after progressDeadlineSeconds?

- **A.** That the rollout succeeded
- **B.** That the Deployment exceeded its progress deadline; the old Pods keep serving
- **C.** That the Deployment was deleted
- **D.** Nothing; rollouts never time out

**54.** Which component adds or removes nodes when Pods cannot be scheduled or nodes are underused?

- **A.** The Horizontal Pod Autoscaler
- **B.** The Vertical Pod Autoscaler
- **C.** The cluster autoscaler (or a node provisioner such as Karpenter)
- **D.** The scheduler

**55.** In distributed tracing, what is a span?

- **A.** A time series of a metric
- **B.** One log line
- **C.** The total latency of the cluster
- **D.** One timed operation within a trace, such as a call from one service to another

**56.** Which tool usually receives alerts from Prometheus and groups, silences, and routes them to email or chat?

- **A.** Alertmanager
- **B.** Grafana Loki
- **C.** Fluent Bit
- **D.** Jaeger

**57.** Which body of the CNCF decides on accepting projects and moving them through the maturity levels?

- **A.** The Linux Foundation's board
- **B.** The Technical Oversight Committee (TOC)
- **C.** The Kubernetes Steering Committee
- **D.** The project's own maintainers

**58.** What is the main benefit of open standards such as OCI, CNI, and CSI for cloud-native users?

- **A.** They make Kubernetes faster
- **B.** They are required by law
- **C.** Components from different vendors work together, so users can choose and replace them without lock-in
- **D.** They remove the need for container runtimes

**59.** What does a site reliability engineer (SRE) typically use to decide whether a service may ship risky changes?

- **A.** The number of Pods
- **B.** The cluster's Kubernetes version
- **C.** The size of the container images
- **D.** The error budget left under its service level objective (SLO)

**60.** A new Kubernetes feature is in alpha. Which statement is true?

- **A.** It is disabled by default behind a feature gate, and may change or be removed without notice
- **B.** It is enabled by default and stable
- **C.** It is only available on managed clusters
- **D.** It cannot be enabled at all

<details>
<summary>Answers</summary>

**1. B.** The controller manager runs many controllers, each watching its kind of object and acting to close the gap between spec and status. The scheduler only assigns Pods to nodes.

**2. C.** Cloud-specific logic (load balancers for LoadBalancer Services, node lifecycle, routes) runs in the cloud-controller-manager, so the core components stay independent of any provider.

**3. D.** The API server is stateless, so instances can run side by side behind a load balancer. The scheduler and the controller manager, in contrast, use leader election so that only one instance acts.

**4. A.** Resources are organized in API groups (apps, batch, networking.k8s.io, ...), each versioned. The core group, for Pods and Services, has no name: its apiVersion is just v1.

**5. B.** OnFailure restarts only containers that exit with a non-zero code. Always restarts any exit (the default for Pods of a Deployment); Never restarts none.

**6. C.** Init containers run one after another, each to completion, before any app container starts. If one fails, the kubelet retries it according to the restart policy.

**7. D.** m means millicores: 1000m is one core, so 250m is a quarter. Memory uses units such as Mi and Gi.

**8. A.** Requests equal to limits for CPU and memory in every container make a Pod Guaranteed; it is the last to be evicted under memory pressure. Some requests or limits make it Burstable, none BestEffort.

**9. B.** A headless Service (clusterIP: None) creates DNS records for each Pod. Combined with the StatefulSet's ordinal names, every replica keeps a name clients can address directly.

**10. C.** completions is how many successful Pods the Job needs; parallelism caps how many run at once. backoffLimit, not parallelism, sets how many failures are tolerated.

**11. D.** Set-based selectors (in, notin, exists) match label values against a set. Deployments, ReplicaSets, Jobs, and kubectl -l support them; a Service's selector is equality-based only.

**12. A.** Owner references link Pods to their ReplicaSet and ReplicaSets to their Deployment. Deleting the owner deletes the dependents in cascade, unless you ask for --cascade=orphan.

**13. B.** Selectors use labels. Annotations carry non-identifying data: change causes, tool settings, build information. Annotation values may be large; label values are short.

**14. C.** -o wide adds columns such as IP and NODE. --show-labels adds labels, -o name prints only names, and kubectl top shows resource usage.

**15. D.** A write needs a majority. Three members need two and tolerate one failure; four need three and still tolerate only one. Five tolerate two.

**16. A.** kubeadm init sets up a control plane, kubeadm join adds nodes, and kubeadm upgrade moves the cluster to a new version. kubectl talks to a running cluster; Helm installs applications.

**17. B.** The kubelet watches a directory (on kubeadm nodes /etc/kubernetes/manifests) and runs every Pod defined there. The API server shows a read-only mirror Pod. kubeadm runs the control plane this way.

**18. C.** Preferred rules are soft: they raise the score of matching nodes. Required rules are hard and keep the Pod Pending if no node matches. IgnoredDuringExecution means running Pods are not moved later.

**19. D.** topologySpreadConstraints set how unevenly matching Pods may be distributed (maxSkew) across a topology key such as topology.kubernetes.io/zone, so that one zone failing does not take every replica.

**20. A.** With a PriorityClass, the scheduler orders Pending Pods by priority and may preempt lower-priority Pods. Adding nodes is the cluster autoscaler's job, not the scheduler's.

**21. B.** The node lifecycle controller taints the node. Pods tolerate that taint for 300 seconds by default; then they are evicted and their controllers create new Pods elsewhere. Containers are not moved live.

**22. C.** The final stage starts FROM a minimal base and copies the built artifact from an earlier stage, so compilers and build dependencies do not end up in the image that runs.

**23. D.** containerd or CRI-O handle images and the CRI, then call an OCI runtime such as runc to actually start the container. Sandboxed runtimes such as gVisor's runsc replace runc.

**24. A.** The kubelet asks the runtime to pull the image named in the Pod spec from its registry. Private registries need credentials, given to the Pod as an imagePullSecret.

**25. B.** IfNotPresent uses a cached copy when there is one. Always checks the registry every time (the default for the latest tag or no tag). Never uses only local images.

**26. C.** Separating configuration from the image (one of the twelve-factor principles) lets the same tested image move from staging to production unchanged.

**27. D.** Without a virtual IP, DNS answers with the ready Pods' addresses, and clients connect to them directly. StatefulSets use headless Services for stable per-Pod names.

**28. A.** The EndpointSlice controller keeps a list of ready Pod IPs and ports for each Service. kube-proxy reads them to program the node's forwarding rules.

**29. B.** The Gateway API separates what infrastructure providers, cluster operators, and application teams manage, and adds features such as weighted backends. Like Ingress, it needs an implementation.

**30. C.** A Pod's resolv.conf lists search domains starting with its own Namespace (shop.svc.cluster.local), so db resolves to db.shop.svc.cluster.local. Other Namespaces need db.other.

**31. D.** CoreDNS runs as a Deployment behind the kube-dns Service and serves records for Services and Pods. kube-proxy handles Service traffic, not names.

**32. A.** kube-proxy programs the node's packet filter: iptables (the long-time default), IPVS, or nftables. Some CNI plugins, such as Cilium, can replace kube-proxy entirely.

**33. B.** namespaceSelector selects whole Namespaces by their labels. To require a Pod label as well, put a podSelector in the same from entry.

**34. C.** A RoleBinding grants permissions within its own Namespace, even when the role it refers to is a ClusterRole. That lets one ClusterRole (for example view) be reused per Namespace.

**35. D.** Admission comes after authentication and authorization. Mutating admission can change the object; validating admission can only accept or reject it, for example to enforce policies.

**36. A.** allowPrivilegeEscalation: false sets the no_new_privs flag on the container's processes. The restricted Pod Security level requires it.

**37. B.** CSI drivers let any storage system provision and attach volumes without changes to Kubernetes itself. Most in-tree volume plugins have been migrated to CSI.

**38. C.** Delete removes the volume with its claim; Retain keeps the PersistentVolume and its data, which an administrator must clean up or reuse by hand.

**39. D.** ReadWriteMany needs storage that supports it, such as NFS or a shared file system. Block storage such as cloud disks usually offers only ReadWriteOnce.

**40. A.** A claim binds to a matching PersistentVolume or gets one from its StorageClass. kubectl describe pvc shows the reason in its events; WaitForFirstConsumer classes wait for a Pod by design.

**41. B.** 137 is 128 plus signal 9 (SIGKILL). OOMKilled means the out-of-memory killer acted because the container used more memory than its limit. Raise the limit or fix the leak.

**42. C.** Ready comes from the kubelet's status reports. describe node shows the conditions and their messages; on the node, systemctl status kubelet and its journal, and the runtime's status, give the cause.

**43. D.** Pod Security Admission is built into the API server. Labels such as pod-security.kubernetes.io/enforce=restricted on a Namespace decide which level applies there and what happens to violations.

**44. A.** Helm keeps a history of each release's revisions. helm rollback RELEASE REVISION applies the manifests of that revision again, as a new revision.

**45. B.** Argo CD and Flux are CNCF graduated GitOps projects. They pull the desired state from Git (or OCI registries) and reconcile continuously; they do not build images.

**46. C.** Templates read .Values. A values file (-f values.yaml) or --set overrides the defaults in the chart's own values.yaml. Chart.yaml holds the name, version, and dependencies.

**47. D.** Continuous integration builds, tests, and publishes an artifact. Continuous delivery then deploys that artifact to environments, often through GitOps by updating the image reference in Git.

**48. A.** latest can point to a different image tomorrow, so the same manifest could run different code. Digests are immutable; unique tags are close, as long as nobody moves them.

**49. B.** Each change to the Pod template creates a ReplicaSet; old ones are scaled to zero and kept, up to revisionHistoryLimit (10 by default), so that kubectl rollout undo can return to them.

**50. C.** -f (follow) streams new lines. --previous shows the logs of the container's last, crashed instance; get -w watches the object's status, not its logs.

**51. D.** Components record what they do to an object as events: Scheduled, Pulling, Failed, Unhealthy. They are kept for a limited time (one hour by default).

**52. A.** kubectl debug on a node starts a Pod in the node's host namespaces with its root file system under /host, useful when you cannot SSH to the node.

**53. B.** With the default rolling update, old Pods stay until new ones are ready. After progressDeadlineSeconds (600 by default) the Deployment's Progressing condition turns False; kubectl rollout undo returns to the previous version.

**54. C.** The HPA changes replica counts, the VPA changes requests, and the cluster autoscaler changes the number of nodes, based on Pending Pods and node usage.

**55. D.** A trace follows one request through many services; it is made of spans, each with a start, a duration, and attributes, linked by a trace ID that is passed along with the request.

**56. A.** Prometheus evaluates alerting rules and sends firing alerts to Alertmanager, which deduplicates, groups, silences, and routes them. Loki stores logs, Fluent Bit ships them, and Jaeger stores traces.

**57. B.** The CNCF TOC defines the technical vision and votes on sandbox admission, incubation, and graduation. The Kubernetes Steering Committee governs only the Kubernetes project.

**58. C.** Shared interfaces let any compliant runtime, network plugin, or storage driver plug into Kubernetes. The same image runs on any OCI runtime.

**59. D.** An SLO (for example 99.9% of requests succeed) leaves a small budget for failure. While budget remains, teams can move fast; when it is spent, reliability work comes first.

**60. A.** Alpha features are off by default and carry no compatibility promise. Beta features are better tested (new beta APIs are off by default); GA features are stable and on.

</details>

<!-- QUESTIONS:END -->
