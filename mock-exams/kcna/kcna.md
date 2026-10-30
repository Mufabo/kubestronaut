# Mock exam: KCNA practice exam

> **Exam:** KCNA
> **Format:** 60 multiple-choice questions, 90 minutes, pass mark 75%
> **Covers:** the four KCNA domains, weighted as in the curriculum: Kubernetes Fundamentals 44% (26 questions), Container Orchestration 28% (17), Cloud Native Application Delivery 16% (10), Cloud Native Architecture 12% (7)
> **Lab tier:** none (no cluster needed)
> **Prerequisites:** the KCNA study plan in Chapter 39

The KCNA is a multiple-choice exam, so this mock exam has no lab. Take it in the
terminal, timed, the way the real exam runs:

```bash
make quiz EXAM=kcna          # start, or resume, an attempt; the clock starts with the first question
make quiz-reset EXAM=kcna    # throw the attempt away and start over
```

Each attempt shows the questions in a new order. Answer with a letter; you can go
back and forth, flag questions, and see a review of what is answered and
flagged. Your answers are saved after every step, so you can close the terminal
and resume, but the clock keeps running, as in the real exam. When you submit, or
when the 90 minutes are up, you get your score per domain, and the explanation of
every question you missed.

The questions are original and written from the public curriculum only; they are
not real exam questions. They are also listed below, in curriculum order, with
the answers hidden at the end. Use the list to review after an attempt, not to
take the exam: reading them in order gives away the domain of each question.

<!-- QUESTIONS:START -->

## Questions

**1.** You create a Deployment with kubectl. Which component writes the object to persistent storage?

- **A.** The kubelet on the node that runs the Pods
- **B.** The kube-apiserver, which stores it in etcd
- **C.** The kube-controller-manager
- **D.** kubectl writes it to etcd directly

**2.** A new Pod has no node yet. Which component chooses one for it?

- **A.** kube-proxy
- **B.** The kubelet with the most free memory
- **C.** kube-scheduler
- **D.** etcd

**3.** What does the kubelet do?

- **A.** It runs on every node and makes sure the containers of the Pods assigned to that node are running
- **B.** It routes Service traffic to Pods
- **C.** It stores the cluster's configuration
- **D.** It replaces failed nodes in a cloud provider

**4.** What is the smallest unit that Kubernetes schedules?

- **A.** A container
- **B.** A node
- **C.** A ReplicaSet
- **D.** A Pod

**5.** A Deployment runs three replicas. You delete one of its Pods. What happens?

- **A.** The Deployment now runs two replicas until you scale it again
- **B.** The Deployment is deleted as well
- **C.** The ReplicaSet notices two Pods instead of three and creates a new Pod
- **D.** The deleted Pod is restored with the same name and IP address

**6.** Which object gives a changing set of Pods one stable virtual IP address and DNS name?

- **A.** A Service
- **B.** An Ingress
- **C.** A ConfigMap
- **D.** A Namespace

**7.** A log collector must run exactly one Pod on every node, including nodes added later. Which workload fits?

- **A.** A Deployment with one replica per node
- **B.** A StatefulSet
- **C.** A Job
- **D.** A DaemonSet

**8.** A database needs each replica to keep its name and its own volume across restarts. Which workload fits?

- **A.** A Deployment
- **B.** A ReplicaSet
- **C.** A DaemonSet
- **D.** A StatefulSet

**9.** A report must be generated every night at 02:00 and the Pod must stop when the report is done. Which object do you create?

- **A.** A Deployment with a sleep loop
- **B.** A Job
- **C.** A CronJob
- **D.** A DaemonSet

**10.** Which statement about Namespaces is true?

- **A.** Pods in different Namespaces cannot reach each other over the network
- **B.** Every object in Kubernetes belongs to a Namespace
- **C.** Namespaces scope the names of objects, and quotas and RBAC rules can be applied per Namespace
- **D.** A Namespace is a separate cluster with its own API server

**11.** A Service must select the Pods of one application. Which metadata does its selector match?

- **A.** Annotations
- **B.** The container image names
- **C.** The Pod names
- **D.** Labels

**12.** Which command manages objects declaratively?

- **A.** kubectl apply -f app.yaml
- **B.** kubectl run web --image=nginx
- **C.** kubectl scale deployment web --replicas=3
- **D.** kubectl create deployment web --image=nginx

**13.** Which command prints the documentation of a resource's fields, such as pod.spec.containers?

- **A.** kubectl describe pod.spec.containers
- **B.** kubectl api-resources pod
- **C.** kubectl explain pod.spec.containers
- **D.** kubectl get pod -o docs

**14.** What does a context in a kubeconfig file combine?

- **A.** A cluster, a user, and optionally a default Namespace
- **B.** A node, a Pod, and a container
- **C.** An image, a tag, and a registry
- **D.** A Deployment and its Service

**15.** An etcd cluster has three members. How many can fail while the cluster still accepts writes?

- **A.** None
- **B.** One
- **C.** Two
- **D.** Three

**16.** Which statement about version skew between the API server and the kubelets is true?

- **A.** A kubelet may be newer than the API server
- **B.** Version skew only matters for kubectl
- **C.** All components must run exactly the same patch version
- **D.** A kubelet may be older than the API server, within the supported skew, but never newer

**17.** You must take a node out of service for maintenance. Which command marks it unschedulable and evicts its Pods?

- **A.** kubectl cordon
- **B.** kubectl delete node
- **C.** kubectl drain
- **D.** kubectl taint node --all

**18.** A node has the taint gpu=true:NoSchedule. Which Pods can be scheduled on it?

- **A.** Only Pods with a matching toleration
- **B.** Only Pods with a nodeSelector for gpu=true
- **C.** Any Pod, because taints only affect running Pods
- **D.** No Pods at all

**19.** A Pod must only run on nodes labeled disktype=ssd. What do you add to the Pod?

- **A.** A toleration for disktype=ssd
- **B.** A label disktype=ssd on the Pod
- **C.** An annotation disktype=ssd
- **D.** A nodeSelector, or a required node affinity rule, for disktype=ssd

**20.** Which values does the scheduler use to decide whether a Pod fits on a node?

- **A.** The containers' resource limits
- **B.** The node's current CPU usage
- **C.** The containers' resource requests
- **D.** The size of the container image

**21.** A Pod stays Pending with the event "0/3 nodes are available: 3 Insufficient cpu". What does it mean?

- **A.** No node has enough unrequested CPU for the Pod's CPU request
- **B.** The nodes' CPUs are busy right now
- **C.** The container exceeded its CPU limit
- **D.** The cluster has no CPU limits configured

**22.** What is the relationship between a container image and a container?

- **A.** They are two names for the same thing
- **B.** An image is a running process; a container is the file on disk
- **C.** An image is a read-only template made of layers; a container is a running instance of it
- **D.** A container contains several images

**23.** Which specifications does the Open Container Initiative (OCI) define?

- **A.** The image format, the runtime, and the distribution of container images
- **B.** How the kubelet talks to the container runtime
- **C.** How Pods get their network interfaces
- **D.** How volumes are attached to nodes

**24.** containerd and CRI-O can both run Kubernetes Pods. Which interface do they implement for the kubelet?

- **A.** CNI
- **B.** CSI
- **C.** CRI
- **D.** SMI

**25.** Which Linux kernel features isolate containers and limit their resources?

- **A.** Namespaces for isolation and cgroups for resource limits
- **B.** A hypervisor per container
- **C.** SELinux for isolation and swap for resource limits
- **D.** chroot alone

**26.** Which image reference always resolves to exactly the same image content?

- **A.** nginx:latest
- **B.** nginx:1.27
- **C.** nginx
- **D.** nginx@sha256:DIGEST

**27.** Which statement belongs to the Kubernetes network model?

- **A.** Pods share their node's IP address and use different ports
- **B.** Every Pod gets its own IP address, and Pods can reach each other without NAT
- **C.** Pods can only reach Pods on the same node
- **D.** Each Namespace has its own isolated network

**28.** Which plugin interface sets up the network interfaces and IP addresses of Pods?

- **A.** CRI
- **B.** CSI
- **C.** CNI
- **D.** OCI

**29.** Which Service type opens the same port on every node to reach the Service from outside the cluster?

- **A.** ClusterIP
- **B.** Headless
- **C.** ExternalName
- **D.** NodePort

**30.** In a cluster with the default domain, what is the full DNS name of the Service api in the Namespace shop?

- **A.** api.shop.svc.cluster.local
- **B.** shop.api.cluster.local
- **C.** api.svc.shop.local
- **D.** api.cluster.local/shop

**31.** What does kube-proxy do?

- **A.** It forwards kubectl commands to the API server
- **B.** It runs on each node and programs the rules that send Service traffic to the Pods behind it
- **C.** It is the cluster's DNS server
- **D.** It is an HTTP reverse proxy for Ingress objects

**32.** A Namespace has no NetworkPolicies. What traffic is allowed to its Pods?

- **A.** None until a policy allows it
- **B.** Only traffic from the same Namespace
- **C.** All traffic
- **D.** Only traffic on port 80

**33.** You create an Ingress, but nothing answers on its host name. What is the most likely cause?

- **A.** Ingress objects need a NodePort Service
- **B.** No Ingress controller is running in the cluster
- **C.** Ingress only works for HTTPS
- **D.** The kube-scheduler has not placed the Ingress yet

**34.** A user must read Pods in the Namespace dev only. What is the right combination?

- **A.** A ClusterRole and a ClusterRoleBinding
- **B.** A NetworkPolicy in dev
- **C.** A ServiceAccount in dev
- **D.** A Role in dev and a RoleBinding in dev

**35.** What is a ServiceAccount for?

- **A.** An identity for processes running in Pods when they call the API server
- **B.** A billing account for cloud resources
- **C.** The account humans use to log in to the dashboard
- **D.** A Secret that holds registry passwords

**36.** Which statement about Kubernetes Secrets is true by default?

- **A.** Their values are encrypted with a key that only the Pod knows
- **B.** Their values are base64-encoded, and stored unencrypted in etcd unless encryption at rest is configured
- **C.** They can only be read by the kubelet
- **D.** They are stored outside etcd, in a vault

**37.** Which are the three Pod Security Standards levels?

- **A.** Low, medium, and high
- **B.** Alpha, beta, and stable
- **C.** Open, guarded, and locked
- **D.** Privileged, baseline, and restricted

**38.** Which securityContext setting makes the kubelet refuse to start a container that would run as root?

- **A.** privileged: false
- **B.** readOnlyRootFilesystem: true
- **C.** runAsNonRoot: true
- **D.** allowPrivilegeEscalation: false

**39.** In which order does the API server process a request?

- **A.** Authorization, authentication, admission
- **B.** Admission, authentication, authorization
- **C.** Authentication, authorization, admission
- **D.** Authentication, admission, authorization

**40.** A Pod is in CrashLoopBackOff. Which command most likely shows why?

- **A.** kubectl logs POD --previous
- **B.** kubectl get nodes
- **C.** kubectl top pod POD
- **D.** kubectl get svc

**41.** A Pod shows ImagePullBackOff. Which cause fits?

- **A.** The container ran out of memory
- **B.** The image name or tag is wrong, or the registry needs credentials the Pod does not have
- **C.** The liveness probe failed
- **D.** The node is cordoned

**42.** What creates a PersistentVolume automatically when a PersistentVolumeClaim asks for one?

- **A.** The kubelet
- **B.** A ConfigMap
- **C.** The scheduler
- **D.** A StorageClass with a provisioner (dynamic provisioning)

**43.** A PersistentVolumeClaim has the access mode ReadWriteOnce. What does that allow?

- **A.** Exactly one Pod in the whole cluster may ever use it
- **B.** The volume can be mounted read-write by a single node at a time
- **C.** The volume can be written once and is read-only afterwards
- **D.** Many nodes can mount it read-write

**44.** Which statement describes GitOps?

- **A.** Developers run kubectl apply from their laptops after each commit
- **B.** The desired state lives in Git, and an agent in the cluster pulls it and keeps the cluster in sync
- **C.** Git stores the container images
- **D.** The cluster pushes its state to Git every night as a backup

**45.** What is a Helm chart?

- **A.** A dashboard of cluster metrics
- **B.** A diagram of the cluster's network
- **C.** A list of container images in a registry
- **D.** A package of templated Kubernetes manifests with default values, installed as a release

**46.** How does Kustomize customize manifests for different environments?

- **A.** With a templating language inside the YAML
- **B.** With a base and overlays that patch it, without templates
- **C.** By editing the objects in the cluster after they are created
- **D.** With Helm charts

**47.** A new Deployment version causes errors. Which command returns to the previous version?

- **A.** kubectl rollout undo deployment/web
- **B.** kubectl delete deployment web
- **C.** kubectl scale deployment web --replicas=0
- **D.** kubectl rollout pause deployment/web

**48.** Which deployment strategy sends a small share of the traffic to the new version first and increases it while the version behaves well?

- **A.** Recreate
- **B.** Blue/green
- **C.** Canary
- **D.** Rolling back

**49.** What is the difference between continuous delivery and continuous deployment?

- **A.** There is none
- **B.** Continuous delivery keeps every change ready to release, with a manual approval; continuous deployment releases every passing change automatically
- **C.** Continuous deployment only builds images; continuous delivery runs tests
- **D.** Continuous delivery is for VMs and continuous deployment is for containers

**50.** A Pod runs two containers, app and proxy. How do you read the logs of proxy?

- **A.** kubectl logs POD
- **B.** kubectl describe POD proxy
- **C.** kubectl logs POD -c proxy
- **D.** kubectl exec POD -- logs

**51.** A container's image has no shell. How can you still inspect the running Pod from inside?

- **A.** kubectl exec -it POD -- sh
- **B.** kubectl debug with an ephemeral container that has the tools you need
- **C.** Restart the Pod with a different image tag
- **D.** It is not possible

**52.** A container's readiness probe fails, but its liveness probe passes. What happens?

- **A.** The container is restarted
- **B.** Nothing; readiness probes are informational
- **C.** The Pod is deleted
- **D.** The Pod is removed from its Services' endpoints until the probe passes again

**53.** A Pod is stuck in Pending. Where do you look first for the reason?

- **A.** The container's logs
- **B.** The Pod's events, with kubectl describe pod
- **C.** The node's kernel log
- **D.** The application's metrics

**54.** Which CNCF project provides vendor-neutral APIs, SDKs, and a collector for traces, metrics, and logs?

- **A.** OpenTelemetry
- **B.** Prometheus
- **C.** Fluentd
- **D.** Jaeger

**55.** How does Prometheus usually get metrics from an application?

- **A.** The application pushes every metric to Prometheus
- **B.** Prometheus scrapes an HTTP endpoint, usually /metrics, at a regular interval
- **C.** Prometheus reads the container logs
- **D.** The kubelet forwards metrics to Prometheus

**56.** What are the CNCF's project maturity levels, from youngest to most mature?

- **A.** Alpha, beta, stable
- **B.** Community, enterprise, certified
- **C.** Draft, accepted, certified
- **D.** Sandbox, incubating, graduated

**57.** Which CNCF project scales workloads based on events, such as the length of a message queue, including down to zero?

- **A.** KEDA
- **B.** etcd
- **C.** Harbor
- **D.** CoreDNS

**58.** What does a service mesh such as Istio or Linkerd add to an application?

- **A.** A new programming language
- **B.** A container runtime
- **C.** Persistent storage
- **D.** Mutual TLS, retries, and traffic splitting between services, without changing the application code

**59.** How is a significant new feature proposed for Kubernetes?

- **A.** In a Kubernetes Enhancement Proposal (KEP), owned by a Special Interest Group (SIG)
- **B.** By the CNCF board, which decides alone
- **C.** By any pull request, merged when it passes tests
- **D.** By the cloud providers, in turn

**60.** About how many minor versions of Kubernetes are released each year?

- **A.** One
- **B.** Three
- **C.** Six
- **D.** Twelve

<details>
<summary>Answers</summary>

**1. B.** The API server is the only component that talks to etcd. kubectl, the controllers, the scheduler, and the kubelets all read and write cluster state through the API server.

**2. C.** The scheduler watches for Pods without a node, filters and scores the nodes, and binds the Pod to one. The kubelet on that node then starts its containers.

**3. A.** The kubelet is the node agent: it watches the Pods bound to its node and asks the container runtime, through the CRI, to run their containers. Service traffic is kube-proxy's job, and storage is etcd's.

**4. D.** Kubernetes schedules Pods, not single containers. All containers of a Pod run on the same node and share its network namespace and volumes.

**5. C.** The ReplicaSet controller compares the desired count with the actual Pods and creates a replacement. The new Pod gets a new name and, usually, a new IP address.

**6. A.** A Service selects Pods by label and keeps a stable cluster IP and DNS name while the Pods behind it come and go. An Ingress routes HTTP traffic to Services; it does not replace them.

**7. D.** A DaemonSet runs one Pod on each matching node and adds a Pod when a node joins. A Deployment's replica count does not follow the number of nodes.

**8. D.** A StatefulSet gives each replica a stable ordinal name (db-0, db-1) and, through volumeClaimTemplates, a PersistentVolumeClaim of its own that survives the Pod.

**9. C.** A CronJob creates a Job on a schedule, and the Job runs Pods to completion. A Job alone runs once; a Deployment restarts its Pods when they exit.

**10. C.** Namespaces group and scope objects. They do not isolate the network (that needs NetworkPolicies), and some objects, such as Nodes, PersistentVolumes, and ClusterRoles, are cluster-scoped.

**11. D.** Selectors match labels. Annotations hold non-identifying information, such as build details or tool settings, and are never used for selection.

**12. A.** With kubectl apply you describe the desired state in files, and Kubernetes works out the changes. run, create, and scale are imperative: each states one action.

**13. C.** kubectl explain reads the API schema from the cluster and describes each field. describe shows the state of existing objects, and api-resources lists the resource types.

**14. A.** A context names a cluster and the credentials (user) to reach it, and can set a default Namespace. kubectl config use-context switches between them.

**15. B.** etcd needs a majority (quorum) to write: two of three. With one member down, two remain and the cluster works; with two down, it cannot write. This is why etcd clusters have an odd number of members.

**16. D.** The control plane is upgraded first, so kubelets may lag behind the API server by a few minor versions. A kubelet newer than the API server is not supported.

**17. C.** kubectl drain cordons the node and then evicts its Pods, respecting PodDisruptionBudgets. cordon alone only stops new Pods from being scheduled there.

**18. A.** A NoSchedule taint repels Pods that do not tolerate it. A toleration allows a Pod onto the node but does not attract it there; to steer a Pod to the node, add a nodeSelector or node affinity as well.

**19. D.** nodeSelector and required node affinity restrict a Pod to nodes with matching labels. Labels on the Pod itself describe the Pod, not where it may run.

**20. C.** The scheduler adds up the requests of the Pods on each node and compares them with the node's allocatable resources. Limits are enforced at runtime, and actual usage plays no part in scheduling.

**21. A.** Scheduling compares requests with what is still unrequested on each node. Lower the request, free capacity, or add a node; the current load of the CPUs is not the reason.

**22. C.** An image bundles the file system layers and metadata. Starting it creates a container: a process with a writable layer on top of the image.

**23. A.** OCI defines the image, runtime, and distribution specifications. The kubelet's interface to the runtime is the CRI, Pod networking is the CNI, and volume plugins are the CSI.

**24. C.** The Container Runtime Interface lets the kubelet work with any runtime that implements it. Docker Engine itself does not implement the CRI, which is why Kubernetes removed its dockershim.

**25. A.** Namespaces give a container its own view of processes, network, and mounts; cgroups limit its CPU and memory. Containers share the host's kernel, unlike virtual machines.

**26. D.** A digest is the hash of the image manifest, so it cannot point to different content. Tags, including version tags, can be moved to a new image.

**27. B.** Every Pod has a unique IP, and any Pod can reach any other Pod directly, across nodes, without address translation. The network plugin implements this; NetworkPolicies can restrict it.

**28. C.** The Container Network Interface is how runtimes call network plugins such as Calico or Cilium. Without one, nodes stay NotReady and Pods get no network.

**29. D.** A NodePort Service listens on a port (by default 30000–32767) on every node. ClusterIP is internal only, ExternalName is a DNS alias, and a LoadBalancer Service builds on a NodePort.

**30. A.** Service names follow SERVICE.NAMESPACE.svc.CLUSTER-DOMAIN. From the same Namespace, the short name api is enough; from another Namespace, api.shop works.

**31. B.** kube-proxy watches Services and their endpoints and programs iptables, IPVS, or nftables rules on each node. DNS is CoreDNS, and Ingress needs an Ingress controller.

**32. C.** Without policies, everything is allowed. Once a policy selects a Pod for ingress, only the traffic that some policy allows reaches it. Enforcement also needs a network plugin that supports NetworkPolicies.

**33. B.** An Ingress is only a set of rules. An Ingress controller, such as Traefik or the NGINX controller, must watch them and route the traffic. The same holds for the Gateway API and its implementations.

**34. D.** A Role grants permissions within one Namespace, and a RoleBinding gives them to a user, group, or ServiceAccount there. A ClusterRoleBinding would grant the permissions in every Namespace.

**35. A.** ServiceAccounts are Namespace-scoped identities for workloads. Kubernetes has no user objects for humans; people authenticate with certificates, tokens, or an identity provider.

**36. B.** Base64 is an encoding, not encryption. Protect Secrets with RBAC, enable encryption at rest in the API server, or use an external secrets manager.

**37. D.** Privileged allows everything, baseline blocks known privilege escalations, and restricted enforces current hardening practice. Pod Security Admission applies them per Namespace through labels.

**38. C.** With runAsNonRoot, the kubelet checks the user the container would run as and refuses UID 0. The other settings harden the container in other ways.

**39. C.** First the API server establishes who you are, then whether you may do it (RBAC), and then admission controllers may change or reject the object before it is stored.

**40. A.** CrashLoopBackOff means the container starts and exits again and again. The logs of the previous, crashed instance usually show the error; kubectl describe shows the exit code.

**41. B.** The kubelet could not pull the image and is backing off between attempts. Check the image reference in the events, and an imagePullSecret for a private registry.

**42. D.** A claim names a StorageClass; its provisioner, usually a CSI driver, creates a matching volume and PersistentVolume. Without one, an administrator must create PersistentVolumes in advance.

**43. B.** ReadWriteOnce limits the volume to one node; several Pods on that node can share it. ReadWriteOncePod limits it to a single Pod, and ReadWriteMany allows many nodes.

**44. B.** In GitOps, Git is the source of truth, and a controller such as Argo CD or Flux reconciles the cluster with it continuously. Changes go through commits and reviews, not direct kubectl calls.

**45. D.** Helm renders a chart's templates with values and installs the result as a release, which it can upgrade and roll back.

**46. B.** Kustomize combines plain YAML bases with overlays of patches, names, and labels. It is built into kubectl: kubectl apply -k.

**47. A.** Each change to the Pod template creates a new ReplicaSet, and rollout undo scales the previous one up again. pause only stops a rollout where it is.

**48. C.** A canary release exposes a few users to the new version before all of them. Blue/green switches all traffic from one complete environment to another at once; Recreate stops the old version before starting the new one.

**49. B.** Both automate building and testing. The difference is the last step: a person approves the release in continuous delivery, while continuous deployment releases automatically.

**50. C.** With more than one container, kubectl logs needs -c to choose one (or --all-containers). Logs are whatever the container writes to stdout and stderr.

**51. B.** kubectl debug adds an ephemeral container with its own image to the running Pod, so you can inspect it without changing the original image. exec needs a shell inside the image.

**52. D.** Readiness controls whether a Pod receives Service traffic. A failing liveness probe restarts the container; a failing readiness probe only takes the Pod out of rotation.

**53. B.** A Pending Pod has no running container yet, so it has no logs. The events show why: the scheduler's message, a missing volume, or a quota.

**54. A.** OpenTelemetry standardizes how telemetry is produced and collected. Prometheus stores and queries metrics, Fluentd collects logs, and Jaeger stores and shows traces.

**55. B.** Prometheus pulls metrics from its targets and stores them as time series, which you query with PromQL. A Pushgateway exists for short-lived jobs, but pull is the default.

**56. D.** Projects enter the sandbox, move to incubating as adoption grows, and graduate when they show wide adoption and mature governance. Alpha, beta, and stable describe Kubernetes features, not CNCF projects.

**57. A.** KEDA feeds external event sources into the Horizontal Pod Autoscaler and can scale a Deployment to zero. etcd is a key-value store, Harbor a registry, and CoreDNS a DNS server.

**58. D.** A mesh puts proxies (sidecars, or node proxies in ambient mode) in the traffic path and manages them centrally. The application keeps talking plain HTTP or gRPC.

**59. A.** Kubernetes is organized in SIGs that own areas of the project. Larger changes are designed and tracked in KEPs, and move through alpha, beta, and stable stages.

**60. B.** Kubernetes releases about three minor versions a year, roughly every four months. Each minor version receives patches for about 14 months.

</details>

<!-- QUESTIONS:END -->
