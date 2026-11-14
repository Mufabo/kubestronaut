# Mock exam: KCSA practice exam

> **Exam:** KCSA
> **Format:** 60 multiple-choice questions, 90 minutes, pass mark 75%
> **Covers:** the six KCSA domains, weighted as in the curriculum: Overview of Cloud Native Security 14% (8 questions), Kubernetes Cluster Component Security 22% (13), Kubernetes Security Fundamentals 22% (13), Kubernetes Threat Model 16% (10), Platform Security 16% (10), Compliance and Security Frameworks 10% (6)
> **Lab tier:** none (no cluster needed)
> **Prerequisites:** the KCSA study plan in Chapter 39

The KCSA is a multiple-choice exam, so this mock exam has no lab. Take it in the
terminal, timed, the way the real exam runs:

```bash
make quiz EXAM=kcsa          # start, or resume, an attempt; the clock starts with the first question
make quiz-reset EXAM=kcsa    # throw the attempt away and start over
```

Each attempt shows the questions in a new order. Answer with a letter; you can go
back and forth, flag questions, and see a review of what is answered and
flagged. Your answers are saved after every step, so you can close the terminal
and resume, but the clock keeps running, as in the real exam. When you submit, or
when the 90 minutes are up, you get your score per domain, and the explanation of
every question you missed.

The questions are original and written from the public curriculum only; they are
not real exam questions. They draw on Part IV (Chapters 29 to 36) and on the
architecture, networking, and RBAC chapters before it. They are also listed below,
in curriculum order, with the answers hidden at the end. Use the list to review
after an attempt, not to take the exam: reading them in order gives away the
domain of each question.

<!-- QUESTIONS:START -->

## Questions

**1.** In the 4Cs model of cloud native security, which layer is the innermost one, whose security depends on every layer around it?

- **A.** Cloud
- **B.** Cluster
- **C.** Container
- **D.** Code

**2.** Your team uses a managed Kubernetes service from a cloud provider. Who is normally responsible for the RBAC rules that decide what your developers may do in the cluster?

- **A.** The cloud provider, as part of the managed control plane
- **B.** Your team, as the cluster's user
- **C.** The CNCF, through the Kubernetes defaults
- **D.** Nobody: managed clusters have no RBAC

**3.** Which isolation technique gives each Pod a kernel of its own?

- **A.** Kata Containers, which runs each Pod in a lightweight virtual machine
- **B.** A separate Namespace per team
- **C.** A NetworkPolicy that denies all traffic
- **D.** The Pod Security level restricted

**4.** What does referring to an image by digest (name@sha256:...) guarantee that a tag does not?

- **A.** The image has been scanned for vulnerabilities
- **B.** The image was signed by its publisher
- **C.** Every pull returns exactly the same content, because the digest is a hash of it
- **D.** The image is pulled from a private registry

**5.** Why do security guides recommend minimal or distroless base images?

- **A.** They make containers start without a container runtime
- **B.** They contain fewer packages, so fewer vulnerabilities, and often no shell or package manager an attacker could use
- **C.** They encrypt the application's files
- **D.** They are required by Pod Security restricted

**6.** A developer commits a cloud API key to the application's Git repository. Which control is meant to catch this before the image is built and deployed?

- **A.** A NetworkPolicy
- **B.** Encryption at rest for Secrets
- **C.** Pod Security baseline
- **D.** Secret scanning in the CI pipeline or as a commit hook

**7.** On a cloud VM, any Pod can reach the instance metadata endpoint 169.254.169.254 and read the node's cloud credentials. Which control limits this from inside the cluster?

- **A.** A NetworkPolicy whose egress rules exclude 169.254.169.254/32
- **B.** Encrypting Secrets at rest
- **C.** Running the Pod with readOnlyRootFilesystem
- **D.** Pinning images by digest

**8.** What does defense in depth mean for a Kubernetes platform?

- **A.** Running every workload in its own cluster
- **B.** Choosing the single strongest control and relying on it
- **C.** Layering independent controls, so that the failure of one does not expose everything
- **D.** Encrypting data twice

**9.** Anonymous authentication is enabled on the API server. A request arrives with no credentials. As whom is it treated?

- **A.** As the user system:anonymous in the group system:unauthenticated
- **B.** As cluster-admin, because no user was given
- **C.** As the default ServiceAccount of the default Namespace
- **D.** It is always rejected before authorization

**10.** kubeadm starts kube-controller-manager with --use-service-account-credentials=true. What does that achieve?

- **A.** The controller manager stops needing a kubeconfig
- **B.** Each controller uses its own ServiceAccount, so its permissions can be limited to what that controller needs
- **C.** ServiceAccount tokens are no longer issued to Pods
- **D.** Controllers run as Pods in kube-system

**11.** Why does kubeadm make kube-scheduler and kube-controller-manager listen only on 127.0.0.1?

- **A.** Because they cannot use TLS
- **B.** So that the API server can reach them through a Service
- **C.** So that their HTTPS endpoints (health, metrics, profiling) are reachable only from the control plane node itself
- **D.** To save memory

**12.** Which kubelet setting is a security risk on a production node?

- **A.** authorization.mode: Webhook
- **B.** authentication.anonymous.enabled: false
- **C.** rotateCertificates: true
- **D.** readOnlyPort: 10255

**13.** An attacker can reach a kubelet's port 10250, and the kubelet allows anonymous requests with AlwaysAllow authorization. What can the attacker do?

- **A.** Only read the node's CPU usage
- **B.** Nothing, because 10250 is a metrics port
- **C.** Change the API server's flags
- **D.** List the node's Pods and run commands in their containers

**14.** A Pod mounts the host's /run/containerd/containerd.sock. Why is that dangerous?

- **A.** It slows down image pulls
- **B.** Whoever controls the Pod can create and control any container on the node, including privileged ones
- **C.** The socket only allows reading logs
- **D.** It breaks the Pod's DNS resolution

**15.** kube-proxy runs on every node with host networking and elevated privileges. Why does it need them?

- **A.** To program the node's packet filtering rules (iptables, IPVS, or nftables) that implement Services
- **B.** To schedule Pods onto the node
- **C.** To store Service definitions in etcd
- **D.** To terminate TLS for Ingress objects

**16.** What does hostPID: true give a Pod's containers?

- **A.** A process ID of 1 for the application
- **B.** Their own PID namespace with stronger isolation
- **C.** A view of every process on the node, and the ability to signal or inspect them as permissions allow
- **D.** Access to the host's network interfaces

**17.** Who should be able to connect to etcd's client port (2379) in a kubeadm cluster?

- **A.** Every Pod, so that applications can store configuration
- **B.** Every node's kubelet
- **C.** Any user with a valid kubeconfig
- **D.** Only the API server (and backup tooling), authenticated with client certificates from etcd's own CA

**18.** Why must etcd snapshots be protected as carefully as etcd itself?

- **A.** They contain every object in the cluster, including Secrets, which are unencrypted unless encryption at rest is on
- **B.** They contain the nodes' SSH keys
- **C.** They can only be restored once
- **D.** They store the container images

**19.** A new cluster has no NetworkPolicies. Which Pods can open connections to a database Pod?

- **A.** Only Pods in the same Namespace
- **B.** Only Pods with the same labels
- **C.** Every Pod in the cluster, in any Namespace
- **D.** None, until a NetworkPolicy allows it

**20.** A user's kubeconfig with a client certificate has leaked. Why is this hard to contain?

- **A.** The certificate is also the cluster's CA
- **B.** Kubernetes cannot revoke a single client certificate; it stays valid until it expires, so you must remove the RBAC bindings for that identity (or replace the CA)
- **C.** Client certificates never expire
- **D.** The kubeconfig contains the etcd password

**21.** Which volume type lets a Pod read and write files on the node itself?

- **A.** emptyDir
- **B.** configMap
- **C.** projected
- **D.** hostPath

**22.** Which setting does Pod Security restricted require that baseline does not?

- **A.** No privileged containers
- **B.** runAsNonRoot: true
- **C.** No hostNetwork
- **D.** No hostPath volumes

**23.** You add the label pod-security.kubernetes.io/enforce=restricted to a Namespace whose Pods violate it. What happens to those running Pods?

- **A.** They keep running; only new Pods are checked
- **B.** They are evicted at once
- **C.** They are restarted with the missing settings added
- **D.** The label is rejected while violating Pods exist

**24.** What does the label pod-security.kubernetes.io/enforce-version=v1.37 on a Namespace do?

- **A.** It requires every Pod to run Kubernetes v1.37 images
- **B.** It enforces only the checks introduced in v1.37
- **C.** It pins the level's checks to those of release v1.37, so an upgrade does not change what is enforced
- **D.** It marks the Namespace as deprecated after v1.37

**25.** How are human users represented in Kubernetes?

- **A.** As User objects stored in etcd
- **B.** As ServiceAccounts in the kube-system Namespace
- **C.** As entries in a users ConfigMap
- **D.** They are not stored at all: the API server learns the user name and groups from the credential (certificate, token, or OIDC) on each request

**26.** What is true of the ServiceAccount tokens the kubelet mounts into Pods today?

- **A.** They never expire and are stored in a Secret
- **B.** They are bound tokens with an expiry and an audience, refreshed by the kubelet, and invalid once the Pod is deleted
- **C.** They contain the ServiceAccount's RBAC rules
- **D.** They are shared by every Pod in the Namespace

**27.** A cluster runs with --authorization-mode=Node,RBAC. How is a request authorized?

- **A.** Both authorizers must allow it
- **B.** Only the last authorizer in the list is used
- **C.** The authorizers are asked in order; the first to allow or deny decides, and if none does, the request is denied
- **D.** The Node authorizer applies to users, RBAC to ServiceAccounts

**28.** A Secret's data field holds cGFzc3dvcmQ=. What protection does that encoding give?

- **A.** None: it is base64, which anyone can decode
- **B.** AES encryption with the cluster's key
- **C.** A hash that cannot be reversed
- **D.** Encryption with the ServiceAccount's key

**29.** Why is the RBAC verb list on Secrets as sensitive as get?

- **A.** list only returns the names of Secrets
- **B.** list returns every Secret in the Namespace, values included
- **C.** list is only allowed for cluster-admin
- **D.** list triggers an audit alert

**30.** Which encryption-at-rest provider keeps the key-encryption key outside the control plane nodes?

- **A.** identity
- **B.** aescbc
- **C.** kms v2
- **D.** secretbox

**31.** Two teams share a cluster, each in its own Namespace. What does the Namespace boundary isolate by itself?

- **A.** Their network traffic
- **B.** Their nodes and kernels
- **C.** Their CPU and memory
- **D.** Their object names, and the scope of RBAC Roles, quotas, and policies they can be given

**32.** Which audit level records who read a Secret, but not the Secret's value?

- **A.** Metadata
- **B.** Request
- **C.** RequestResponse
- **D.** None

**33.** A Namespace has a NetworkPolicy that denies all ingress, and another that allows ingress to app=api from app=web. Can app=web reach app=api?

- **A.** No: the deny policy wins
- **B.** Only if the policies are merged into one
- **C.** Yes: NetworkPolicies are additive, and any policy that allows a connection makes it allowed
- **D.** Only if they run on the same node

**34.** You create NetworkPolicies in a cluster, and traffic is not affected at all. What is the most likely cause?

- **A.** NetworkPolicies take a day to apply
- **B.** The CNI plugin does not enforce NetworkPolicies
- **C.** The API server needs a restart
- **D.** NetworkPolicies apply only to Services

**35.** Which data flow crosses from the control plane into a worker node when you run kubectl exec?

- **A.** etcd connects to the container directly
- **B.** The scheduler opens a shell on the node
- **C.** The API server connects to the kubelet on that node, which runs the command through the container runtime
- **D.** kubectl connects to the container's IP address

**36.** An attacker with root on a control plane node writes a Pod manifest into /etc/kubernetes/manifests. Why is that an effective persistence technique?

- **A.** The kubelet runs it as a static Pod; deleting its mirror Pod through the API does not stop it
- **B.** The scheduler ignores the file
- **C.** It disables audit logging
- **D.** It encrypts etcd

**37.** A Pod without memory limits leaks memory until its node runs out. Which controls prevent this kind of denial of service?

- **A.** Pod Security baseline
- **B.** Memory limits on containers, enforced per Namespace with LimitRanges and ResourceQuotas
- **C.** A NetworkPolicy
- **D.** Encryption at rest

**38.** Which API server feature keeps one noisy client from starving everyone else of API requests?

- **A.** Pod Security Admission
- **B.** The Node authorizer
- **C.** Encryption at rest
- **D.** API Priority and Fairness

**39.** A compromised image runs a crypto miner in a Pod. Which signals would reveal it?

- **A.** Unexpected processes and outbound connections reported by runtime monitoring such as Falco, and unusual CPU use in metrics
- **B.** A failed liveness probe only
- **C.** A change in the Pod's labels
- **D.** An entry in the etcd snapshot

**40.** Pod-to-Pod traffic in the cluster is plain HTTP. Which threat does that expose it to?

- **A.** Privilege escalation through RBAC
- **B.** Image tampering in the registry
- **C.** An attacker on the network path (a compromised node or network device) reading or changing the traffic
- **D.** Denial of service by the scheduler

**41.** An attacker gets a shell in a web Pod that never calls the Kubernetes API. Which setting would have left them without an API credential?

- **A.** runAsNonRoot: true
- **B.** automountServiceAccountToken: false
- **C.** A memory limit
- **D.** imagePullPolicy: Always

**42.** Which RBAC permissions let a user grant themselves more permissions than they have?

- **A.** get and list on Pods
- **B.** watch on Events
- **C.** create on ConfigMaps
- **D.** escalate or bind on Roles, and impersonate on users or groups

**43.** A user may only create Pods in the Namespace shop, and has no permissions on Secrets. Why can they still read shop's Secrets?

- **A.** They cannot
- **B.** Creating Pods implies list on Secrets in RBAC
- **C.** They can create a Pod that mounts any Secret of the Namespace, or runs as any of its ServiceAccounts, and read it from inside
- **D.** Secrets are readable by every authenticated user

**44.** What does allowPrivilegeEscalation: false prevent?

- **A.** A process gaining more privileges than its parent, for example through setuid binaries
- **B.** The container running as root
- **C.** The Pod using a ServiceAccount
- **D.** The container reaching the network

**45.** What is a Software Bill of Materials (SBOM) used for?

- **A.** Signing an image
- **B.** Listing the components and versions in an artifact, so that you can find which images contain a newly published vulnerability
- **C.** Encrypting an image in the registry
- **D.** Replacing vulnerability scanning

**46.** How do you make sure the cluster only runs images that your CI pipeline built?

- **A.** Use only images with the tag stable
- **B.** Pull images with imagePullPolicy: Always
- **C.** Sign images in the pipeline (for example with Sigstore cosign) and verify the signatures in an admission controller
- **D.** Store images in etcd

**47.** How do you keep workloads from pulling images from arbitrary public registries?

- **A.** Delete the default ServiceAccount
- **B.** Disable DNS in the cluster
- **C.** Use only private Namespaces
- **D.** An admission policy that allows only images from approved registries, ideally a private registry that mirrors and scans what you use

**48.** Someone deleted a Deployment in production. Which record tells you who did it and when?

- **A.** The Kubernetes audit log
- **B.** The Deployment's events
- **C.** The kubelet's logs
- **D.** The container's logs

**49.** What security property does a service mesh's mTLS add to service-to-service traffic?

- **A.** It replaces RBAC for the Kubernetes API
- **B.** Encryption in transit, and a cryptographic identity for each workload that authorization policies can use
- **C.** It scans images for vulnerabilities
- **D.** It enforces Pod Security Standards

**50.** In a kubeadm cluster, how long are the CA certificate and the component certificates (such as the API server's) valid by default?

- **A.** Both one year
- **B.** Both ten years
- **C.** The CA ten years, the component certificates one year
- **D.** They never expire

**51.** Why does kubeadm give etcd a CA of its own, separate from the cluster CA?

- **A.** etcd cannot read the cluster CA's format
- **B.** To make etcd faster
- **C.** Because etcd runs outside the cluster
- **D.** So that certificates signed by the cluster CA, such as users' client certificates, cannot authenticate to etcd

**52.** Which object restricts which destinations Pods may connect to outside the cluster?

- **A.** A NetworkPolicy with egress rules
- **B.** An Ingress
- **C.** A Service of type LoadBalancer
- **D.** A ResourceQuota

**53.** In which order does the API server run admission for a create request?

- **A.** Validating admission, then mutating admission, then authentication
- **B.** Mutating admission, then schema validation, then validating admission, then storage in etcd
- **C.** Storage first, then admission in the background
- **D.** Only one admission controller runs per request

**54.** A validating admission webhook that enforces security rules has failurePolicy: Ignore. What happens when the webhook is down?

- **A.** All requests are rejected
- **B.** The API server restarts
- **C.** Requests are admitted without the webhook's checks, so its rules are silently not enforced
- **D.** The webhook's last decision is reused

**55.** What does kube-bench do?

- **A.** It load-tests the API server
- **B.** It scans container images for vulnerabilities
- **C.** It enforces Pod Security Standards
- **D.** It checks a cluster's nodes and components against the CIS Kubernetes Benchmark and reports PASS, FAIL, and WARN

**56.** In the STRIDE threat model, which category covers an attacker who can deny having deleted a Deployment because no record of it exists?

- **A.** Repudiation
- **B.** Spoofing
- **C.** Tampering
- **D.** Elevation of privilege

**57.** What is MITRE ATT&CK?

- **A.** A compliance standard for payment data
- **B.** A public knowledge base of attackers' tactics and techniques, with a matrix for containers and Kubernetes
- **C.** A vulnerability scanner
- **D.** A CNCF admission controller

**58.** A cluster processes credit card payments. Which compliance standard applies to it?

- **A.** HIPAA
- **B.** SOC 2 only
- **C.** PCI DSS
- **D.** FedRAMP

**59.** What does the SLSA framework describe?

- **A.** Service level agreements for managed Kubernetes
- **B.** A file format for SBOMs
- **C.** An image signing tool
- **D.** Levels of supply chain integrity for build systems, such as producing signed provenance for each artifact

**60.** Why do platform teams use policy as code (for example Kyverno or OPA Gatekeeper) for compliance?

- **A.** Policies are versioned, reviewed, and enforced automatically at admission, and audits can report existing violations continuously
- **B.** It removes the need for RBAC
- **C.** It encrypts the cluster's data
- **D.** It replaces the CIS Benchmark

<details>
<summary>Answers</summary>

**1. D.** The layers nest: Cloud (or data center) contains the Cluster, which runs Containers, which run your Code. Each layer can only be as secure as the layers outside it, so the application code is the innermost layer.

**2. B.** In the shared responsibility model the provider runs and patches the control plane, but who may do what inside the cluster (RBAC, NetworkPolicies, workload settings) stays the customer's job.

**3. A.** Namespaces, NetworkPolicies, and Pod Security all leave containers on the node's shared kernel. Kata Containers puts each Pod in a small VM with its own guest kernel; gVisor instead intercepts system calls with a user-space kernel.

**4. C.** A tag is a movable pointer: whoever can push to the repository can point it at different content. A digest is a cryptographic hash of the image manifest, so it always names the same content. It says nothing about scans or signatures by itself.

**5. B.** Every package in an image is something to patch and something an attacker can use. A distroless image holds the application and its runtime only. Pod Security does not look at image contents at all.

**6. D.** Credentials in code belong to the Code layer and are caught where the code is: by secret scanners in pre-commit hooks and CI. Once leaked, the key must also be revoked; removing the commit does not remove it from history or from copies.

**7. A.** An egress NetworkPolicy (ipBlock with an except for the metadata address) keeps Pods away from the endpoint. Cloud-side settings help too, such as requiring session tokens (IMDSv2) with a hop limit of 1, and giving the node identity only the permissions it needs.

**8. C.** No control is perfect. If an RBAC rule is too broad, Pod Security, NetworkPolicies, seccomp, and audit logging still limit and reveal what an attacker can do. Each layer covers some failures of the others.

**9. A.** Anonymous requests get the user system:anonymous and the group system:unauthenticated, and authorization then decides. Any RBAC binding to these subjects is effectively public; the safe state is to grant them nothing beyond the health and discovery endpoints.

**10. B.** Without it, every controller acts with the controller manager's own, broad credentials. With it, each controller (deployment-controller, job-controller, ...) has its own identity and RBAC role, which limits what one buggy or abused controller can do.

**11. C.** Neither component needs incoming connections from other machines: they talk to the API server, not the other way round. Binding to the loopback address removes them from the network's attack surface. Disabling profiling (--profiling=false) narrows it further.

**12. D.** The read-only port serves Pod and node information over plain HTTP with no authentication. It should be 0 (off). Webhook authorization, anonymous authentication off, and certificate rotation are the hardened settings.

**13. D.** The kubelet API serves exec, attach, logs, and Pod listings. Open to anonymous users with AlwaysAllow, it hands out command execution in every container on the node. Set anonymous authentication off and authorization mode Webhook, so the API server's RBAC decides.

**14. B.** The runtime socket is an administrative interface to the container runtime: through it a process can start containers with host mounts or privileges, outside Kubernetes' admission control. It is equivalent to root on the node.

**15. A.** kube-proxy watches Services and EndpointSlices and writes the node's NAT and filter rules. That needs the host's network namespace and NET_ADMIN-level privileges, which also makes a compromised kube-proxy powerful on its node.

**16. C.** hostPID puts the containers in the node's PID namespace. They see all processes, including other containers' and the kubelet's, and can read their environment and /proc entries where permissions allow. Pod Security baseline forbids it.

**17. D.** Whoever can talk to etcd can read and change all cluster state, Secrets included, bypassing authentication, authorization, and admission. kubeadm gives etcd its own CA and requires client certificates; firewalls should keep everyone else away from 2379.

**18. A.** A snapshot is a full copy of the cluster's state. Without encryption at rest, Secret values sit in it in plain form; with it, the snapshot is safe only as long as the encryption keys are stored elsewhere.

**19. C.** The Kubernetes network model is flat: every Pod can reach every other Pod. Namespaces do not change that. Isolation starts only when a NetworkPolicy selects a Pod, and only if the CNI plugin enforces policies.

**20. B.** The API server trusts any unexpired certificate signed by its CA and has no revocation list. Remove every RoleBinding and ClusterRoleBinding for the user and its groups, keep certificates short-lived, and prefer OIDC or other tokens for people.

**21. D.** hostPath mounts a path of the node's file system into the container. A hostPath of / or of /etc gives a container the node. Pod Security baseline forbids hostPath; emptyDir, configMap, and projected volumes are managed by the kubelet and safe.

**22. B.** baseline blocks known privilege escalations: privileged containers, host namespaces, hostPath, and more. restricted adds current hardening practice: non-root, seccomp RuntimeDefault or Localhost, no privilege escalation, and capabilities dropped to ALL.

**23. A.** Pod Security Admission is an admission controller: it checks requests to create Pods, not Pods that already run. The label command warns about violating Pods, and they are rejected the next time they are recreated, for example by a rollout.

**24. C.** The Pod Security Standards are refined from release to release. Without a version the label means latest; pinning it keeps the checks stable across upgrades until you have tested the new ones.

**25. D.** Kubernetes has no User object. Authenticators turn each request's credential into a user name and groups: the CN and O of a client certificate, the claims of an OIDC token, and so on. ServiceAccounts are the only identities Kubernetes stores itself, and they are meant for workloads.

**26. B.** Since the TokenRequest API, Pods get projected, time-limited tokens bound to the Pod. Long-lived tokens in Secrets are no longer created automatically; they exist only if someone creates such a Secret on purpose.

**27. C.** Each authorizer can allow, deny, or have no opinion. The first decision wins; with no decision at all the request is forbidden. The Node authorizer only has opinions on kubelets' requests, so everyone else falls through to RBAC.

**28. A.** base64 only makes binary data safe to put in JSON and YAML. Protecting Secrets takes RBAC (who may read them), encryption at rest (how etcd stores them), and care with how Pods consume them.

**29. B.** A list response contains the full objects, data included. Granting list (or watch) on Secrets grants reading all of them; restrict both as carefully as get.

**30. C.** aescbc, aesgcm, and secretbox keep their key in the EncryptionConfiguration file on the control plane node, so whoever reads that file can decrypt. kms v2 uses envelope encryption with a key held by an external key management service. identity does not encrypt.

**31. D.** A Namespace is a naming and policy scope. Traffic needs NetworkPolicies, resources need ResourceQuotas and LimitRanges, and nodes and kernels need taints, affinity, or sandboxed runtimes to be separated.

**32. A.** Metadata records the user, verb, resource, name, source address, and result. Request and RequestResponse add the bodies, which for Secrets means their values; None records nothing.

**33. C.** NetworkPolicies only allow; there is no deny rule. A Pod selected by any policy is isolated, and a connection is allowed if at least one policy allows it. That is how default-deny plus specific allows works.

**34. B.** The API server stores NetworkPolicies, but the CNI plugin enforces them. Plugins such as Calico and Cilium do; a plugin that only provides connectivity accepts the objects and ignores them.

**35. C.** exec, logs, attach, and port-forward go from the client to the API server, and from the API server to the kubelet's port 10250. That is why the kubelet's API is a trust boundary worth hardening: whoever reaches it directly skips the API server's checks.

**36. A.** The kubelet starts every manifest in its static Pod directory and restarts it when it stops. The API only shows a read-only mirror Pod; the Pod disappears only when the file is removed from the node.

**37. B.** A limit makes the kernel stop one container (OOM kill) before the node suffers. LimitRanges give containers defaults and maximums, and ResourceQuotas cap a Namespace's total, so one workload cannot starve the others.

**38. D.** API Priority and Fairness sorts requests into priority levels and queues them fairly between flows, so a misbehaving controller or client cannot crowd out the control plane's own requests.

**39. A.** Malicious code changes behavior: new processes, network connections to mining pools, and CPU usage far above normal. Runtime detection and metrics see this; admission control does not, because the image looked fine when it was admitted.

**40. C.** Unencrypted traffic can be sniffed and modified by anyone positioned on its path. mTLS, from a service mesh or a CNI plugin with encryption, protects it in transit and authenticates both ends.

**41. B.** By default every Pod gets its ServiceAccount's token in /var/run/secrets/kubernetes.io/serviceaccount. A Pod that does not need the API should not have it: set automountServiceAccountToken: false on the Pod or its ServiceAccount.

**42. D.** RBAC normally prevents creating a binding to permissions you do not hold. escalate and bind lift that check; impersonate lets you act as another identity. All three amount to privilege escalation and belong only to administrators.

**43. C.** A Pod can reference every Secret and ServiceAccount in its Namespace. Create on Pods is therefore as sensitive as reading those Secrets and using those identities; admission policies can narrow what such Pods may reference.

**44. A.** It sets the no_new_privs flag on the container's processes, so setuid and setgid binaries and file capabilities cannot raise privileges. It does not change the user the container starts as; that is runAsUser and runAsNonRoot.

**45. B.** An SBOM (in SPDX or CycloneDX format) inventories what an image is made of. When a vulnerability is announced, SBOMs tell you at once which of your artifacts contain the affected component. It complements scanning, it does not replace it.

**46. C.** A signature ties an image digest to the identity that signed it. A policy engine (Kyverno, Gatekeeper with a provider, or Sigstore's policy-controller) rejects Pods whose images lack a valid signature from your pipeline.

**47. D.** An admission rule (a ValidatingAdmissionPolicy, Kyverno, or Gatekeeper) checks every image reference against an allow list. A private registry adds access control, scanning, and protection from upstream images changing or disappearing.

**48. A.** Only the API server sees every request with its authenticated user, and its audit log records it. Events are short-lived and do not name users; the kubelet and the containers never see API requests.

**49. B.** The mesh's proxies encrypt traffic and present certificates that identify the workload (often as a SPIFFE ID based on its ServiceAccount). Policies can then allow calls by service identity instead of by IP address.

**50. C.** kubeadm creates CAs valid for ten years and leaf certificates valid for one year. kubeadm upgrades renew the leaf certificates; otherwise kubeadm certs renew does, before they expire and break the control plane.

**51. D.** etcd trusts any certificate its CA signed. With a separate etcd CA, only the certificates made for etcd and the API server's etcd client certificate are accepted; a user's cluster certificate gets no access to the data store.

**52. A.** Egress rules in a NetworkPolicy limit outgoing connections, including to IP blocks outside the cluster. Ingress objects and Services expose workloads; they do not limit what Pods connect to.

**53. B.** After authentication and authorization, mutating admission may change the object, the object is validated against its schema, and validating admission (including ValidatingAdmissionPolicies and webhooks) accepts or rejects the final version before it is stored.

**54. C.** Ignore fails open: availability wins over enforcement. Fail rejects matching requests while the webhook is unreachable, which keeps the rules but can block the cluster. Security webhooks usually use Fail, with care for the namespaces the webhook itself runs in.

**55. D.** The CIS Kubernetes Benchmark lists configuration recommendations for the control plane, etcd, and the nodes. kube-bench automates the checks it can, so audits are repeatable; fixing the findings stays your job.

**56. A.** STRIDE stands for Spoofing, Tampering, Repudiation, Information disclosure, Denial of service, and Elevation of privilege. Repudiation threats are countered by trustworthy records, in Kubernetes the audit log.

**57. B.** ATT&CK organizes real attacker behavior into tactics (goals such as persistence or credential access) and techniques. Teams use it to plan detections and to describe incidents in a common language.

**58. C.** PCI DSS governs systems that store, process, or transmit cardholder data: network segmentation, access control, encryption, and logging. HIPAA covers health data in the US, FedRAMP US government cloud services, and SOC 2 is a general audit of controls.

**59. D.** SLSA (Supply-chain Levels for Software Artifacts) defines increasing levels of assurance about how an artifact was built: from documented builds to hardened, isolated builders that produce verifiable provenance.

**60. A.** Written as code, compliance rules go through the same review and testing as other changes, are enforced on every request, and produce reports of resources that violate them. Manual checklists drift; enforced policies do not.

</details>

<!-- QUESTIONS:END -->
