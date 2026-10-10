# Coverage matrix

Purpose: prove that every curriculum item for all five exams is covered by a
chapter, a lab task, and questions. This file is the source of truth for "does
the book cover everything?".

## How to read this file

- **Domains, weights, and bullets are verbatim** from the official curriculum
  PDFs in `cncf/curriculum` (see "Curriculum revisions checked" for the files).
  Their wording is kept exactly, typos included (for example "Servicing and
  Networking" and "API depreciations"), so a later diff against a new PDF is
  meaningful.
- **Chapter** lists every chapter that teaches the bullet; chapter numbers
  follow the plan in `ROADMAP.md`, section 5.
- **Lab** names the hands-on work that exercises it:
  - `02/T1`: Chapter 02 lab, Task 1 (step-by-step labs)
  - `03/a A1`: Chapter 03 lab, part `a`, Task A1
  - `03/final Q1`: Chapter 03 lab, part `final` (exam style), Question 1
  - `P1 Q3`: mock exam `part1` (`mock-exams/part1`), Question 3
- **Questions** are end-of-chapter question IDs from each chapter's `questions.yaml`.
- **Status**:
  - `planned`: no chapter written yet.
  - `partly`: some of the listed chapters are drafted; the rest are planned.
    Read the chapter column to see which.
  - `drafted`: every listed chapter is written and its lab passes CI on a real
    cluster, but it has not been reviewed against the curriculum or completed by
    a beta reader.
  - `verified`: drafted, plus reviewed and completed by a beta reader.
- Re-check every exam against the current PDFs before each edition, and record
  the check in "Curriculum revisions checked".

## KCNA

| Domain | Weight |
|---|---|
| Kubernetes Fundamentals | 44% |
| Container Orchestration | 28% |
| Cloud Native Application Delivery | 16% |
| Cloud Native Architecture | 12% |

The KCNA curriculum lists topics, not tasks, so each row is broad. Chapters
01 to 06 and 28 are the KCNA core; the rest go deeper than the exam needs.

| Domain | Bullet (verbatim) | Chapter | Lab | Questions | Status |
|---|---|---|---|---|---|
| Kubernetes Fundamentals | Kubernetes Core Concepts | 02, 04, 05, 06 | 02/T1-T5, 04/T1-T5, 05/T1-T6 | ch02-q01..q05, q08; ch04-q01, q02, q04; ch05-q01..q03 | partly |
| Kubernetes Fundamentals | Administration | 03, 18, 19, 20 | 03/a, 03/b1, 03/b2p | ch02-q10; ch03-q01, q08 | partly |
| Kubernetes Fundamentals | Scheduling | 02, 17 | 02/T4 | ch02-q02, q12 | partly |
| Kubernetes Fundamentals | Containerization | 01, 04 | 04/T1, 04/T5 | ch01-q04..q06; ch04-q01 | drafted |
| Container Orchestration | Networking | 11, 21 | | | planned |
| Container Orchestration | Security | 23, 29, 33 | 03/b3 | ch03-q05 | partly |
| Container Orchestration | Troubleshooting | 04, 26 | 04/T2; P1 Q3 | ch04-q03, q11 | partly |
| Container Orchestration | Storage | 13 | | | planned |
| Cloud Native Application Delivery | Application Delivery | 14, 16 | | | planned |
| Cloud Native Application Delivery | Debugging | 04, 15 | 04/T2, 04/T3; P1 Q4 | ch04-q03, q11 | partly |
| Cloud Native Architecture | Observability | 01, 15, 28 | | ch01-q10 | partly |
| Cloud Native Architecture | Cloud Native Ecosystem and Principles | 01, 28 | 01 exploration exercise | ch01-q07..q11, q15 | partly |
| Cloud Native Architecture | Could Native Community and Collaboration | 01, 28 | 01 exploration exercise | ch01-q02, q03, q12..q14 | partly |

## CKA

| Domain | Weight |
|---|---|
| Storage | 10% |
| Troubleshooting | 30% |
| Workloads and Scheduling | 15% |
| Servicing and Networking | 20% |
| Cluster Architecture, Installation and Configuration | 25% |

| Domain | Bullet (verbatim) | Chapter | Lab | Questions | Status |
|---|---|---|---|---|---|
| Storage | Implement storage classes and dynamic volume provisioning | 13, 22 | | | planned |
| Storage | Configure volume types, access modes and reclaim policies | 13, 22 | | | planned |
| Storage | Manage persistent volumes and persistent volume claims | 13 | | | planned |
| Troubleshooting | Troubleshoot clusters and nodes | 02, 27 | 02/T1, 02/T3 | ch02-q03, q07 | partly |
| Troubleshooting | Troubleshoot cluster components | 02, 27 | 02/T2, 02/T3; P1 Q14 | ch02-q01..q05, q07 | partly |
| Troubleshooting | Monitor cluster and application resource usage | 10, 15 | | | planned |
| Troubleshooting | Manage and evaluate container output streams | 04, 15 | 04/T3; P1 Q4 | ch04-q11 | partly |
| Troubleshooting | Troubleshoot services and networking | 11, 21, 26 | | | planned |
| Workloads and Scheduling | Understand application deployments and how to perform rolling update and rollbacks | 05 | 05/T1-T6 | ch05-q04..q08, q10..q14 | drafted |
| Workloads and Scheduling | Use ConfigMaps and Secrets to configure applications | 03, 07 | 03/b2 C1, C2; P1 Q11 | | partly (03 creates them; 07 consumes them) |
| Workloads and Scheduling | Configure workload autoscaling | 25 | | | planned |
| Workloads and Scheduling | Understand the primitives used to create robust, self-healing, application deployments | 04, 05, 10 | 04/T5; 05/T1, T2, T5 | ch04-q04, q05; ch05-q01..q03, q06, q07 | partly |
| Workloads and Scheduling | Configure Pod admission and scheduling (limits, node affinity, etc.) | 04, 10, 17 | 04/T4; P1 Q5 | ch04-q07, q09 | partly |
| Servicing and Networking | Understand connectivity between Pods | 11, 21 | | | planned |
| Servicing and Networking | Define and enforce Network Policies | 21, 36 | | | planned |
| Servicing and Networking | Use ClusterIP, NodePort, LoadBalancer service types and endpoints | 03, 11 | 03/b2 C5; P1 Q11 | | partly (03 exposes a Pod; 11 teaches Services) |
| Servicing and Networking | Use the Gateway API to manage Ingress traffic | 12 | | | planned |
| Servicing and Networking | Know how to use Ingress controllers and Ingress resources | 12 | | | planned |
| Servicing and Networking | Understand and use CoreDNS | 11, 21 | | | planned |
| Cluster Architecture, Installation and Configuration | Manage role based access control (RBAC) | 03, 23 | 03/b3; P1 Q13 | ch03-q05, q14 | partly (03 checks permissions; 23 manages RBAC) |
| Cluster Architecture, Installation and Configuration | Prepare underlying infrastructure for installing a Kubernetes cluster | 18 | | | planned |
| Cluster Architecture, Installation and Configuration | Create and manage Kubernetes clusters using kubeadm | 18 | | | planned |
| Cluster Architecture, Installation and Configuration | Manage the lifecycle of Kubernetes clusters | 19, 20 | | | planned |
| Cluster Architecture, Installation and Configuration | Implement and configure a highly-available control plane | 18 | | | planned |
| Cluster Architecture, Installation and Configuration | Use Helm and Kustomize to install cluster components | 14 | | | planned |
| Cluster Architecture, Installation and Configuration | Understand extension interfaces (CNI, CSI, CRI, etc.) | 01, 24 | | ch01-q04, q05 | partly |
| Cluster Architecture, Installation and Configuration | Understand CRDs, install and configure operators | 24 | | | planned |

## CKAD

| Domain | Weight |
|---|---|
| Application Design and Build | 20% |
| Application Deployment | 20% |
| Application Observability and Maintenance | 15% |
| Application Environment, Configuration and Security | 25% |
| Services and Networking | 20% |

| Domain | Bullet (verbatim) | Chapter | Lab | Questions | Status |
|---|---|---|---|---|---|
| Application Design and Build | Define, build and modify container images | 01, 16 | | ch01-q05 | partly (01 explains images; 16 builds them) |
| Application Design and Build | Choose and use the right workload resource (Deployment, DaemonSet, CronJob, etc.) | 05, 08 | 05/T1 | ch05-q09 | partly |
| Application Design and Build | Understand multi-container Pod design patterns (e.g. sidecar, init and others) | 04, 09 | P1 Q10 | ch04-q02 | partly |
| Application Design and Build | Utilize persistent and ephemeral volumes | 13 | | | planned |
| Application Deployment | Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary) | 05, 16 | 05/T5 | ch05-q06, q13 | partly (05 covers rolling update and Recreate; 16 covers blue/green and canary) |
| Application Deployment | Understand Deployments and how to perform rolling updates | 05 | 05/T1-T6 | ch05-q04..q08, q10..q14 | drafted |
| Application Deployment | Use the Helm package manager to deploy existing packages | 14 | | | planned |
| Application Deployment | Kustomize | 14 | | | planned |
| Application Observability and Maintenance | Understand API depreciations | 02, 15 | 02/T5; P1 Q12 | ch02-q09, q11 | partly (02 covers groups and versions; 15 covers deprecations) |
| Application Observability and Maintenance | Implement probes and health checks | 10 | | ch02-q13 (explain only) | planned |
| Application Observability and Maintenance | Use built-in CLI tools to monitor Kubernetes applications | 03, 15 | 03/a A1-A4; 03/final Q2, Q6; P1 Q9 | ch03-q06, q07, q11 | partly |
| Application Observability and Maintenance | Utilize container logs | 04, 15 | 04/T3; P1 Q4 | ch04-q11 | partly |
| Application Observability and Maintenance | Debugging in Kubernetes | 04, 15, 26 | 04/T2; P1 Q3, Q6 | ch04-q03, q11 | partly |
| Application Environment, Configuration and Security | Discover and use resources that extend Kubernetes (CRD, Operators) | 03, 24 | 03/a A6; P1 Q12 | ch03-q12 | partly (03 discovers resource types; 24 teaches CRDs) |
| Application Environment, Configuration and Security | Understand authentication, authorization and admission control | 03, 23, 31 | 03/b3; P1 Q13 | ch03-q05, q14 | partly |
| Application Environment, Configuration and Security | Understand requests, limits, quotas | 04, 10 | 04/T4; P1 Q5 | ch04-q07, q09 | partly (quotas in 10) |
| Application Environment, Configuration and Security | Define resource requirements | 04, 10 | 04/T4; P1 Q5 | ch04-q07, q09 | partly |
| Application Environment, Configuration and Security | Understand ConfigMaps | 03, 07 | 03/b2 C1; P1 Q11 | | partly |
| Application Environment, Configuration and Security | Create & consume Secrets | 03, 07 | 03/b2 C2; P1 Q11 | | partly |
| Application Environment, Configuration and Security | Understand ServiceAccounts | 03, 23 | 03/b2 C3; P1 Q11 | | partly |
| Application Environment, Configuration and Security | Understand Application Security (SecurityContexts, Capabilities, etc.) | 10, 33 | | | planned |
| Services and Networking | Demonstrate basic understanding of NetworkPolicies | 21 | | | planned |
| Services and Networking | Provide and troubleshoot access to applications via services | 03, 11, 26 | 03/b2 C5; P1 Q11 | | partly |
| Services and Networking | Use Ingress rules to expose applications | 12 | | | planned |

## CKS

| Domain | Weight |
|---|---|
| Cluster Setup | 15% |
| Cluster Hardening | 15% |
| System Hardening | 10% |
| Minimize Microservice Vulnerabilities | 20% |
| Supply Chain Security | 20% |
| Monitoring, Logging and Runtime Security | 20% |

| Domain | Bullet (verbatim) | Chapter | Lab | Questions | Status |
|---|---|---|---|---|---|
| Cluster Setup | Use Network security policies to restrict cluster level access | 21, 36 | | | planned |
| Cluster Setup | Use CIS benchmark to review the security configuration of Kubernetes components (etcd, kubelet, kubedns, kubeapi) | 30 | | | planned |
| Cluster Setup | Properly set up Ingress objects with TLS | 12, 30 | | | planned |
| Cluster Setup | Protect node metadata and endpoints | 30, 36 | | | planned |
| Cluster Setup | Verify platform binaries before deploying | 30 | | | planned |
| Cluster Hardening | Use Role Based Access Controls to minimize exposure | 23, 31 | | | planned |
| Cluster Hardening | Exercise caution in using service accounts e.g. disable defaults, minimize permissions on newly created ones | 23 | | | planned |
| Cluster Hardening | Restrict access to Kubernetes API | 30, 31 | | | planned |
| Cluster Hardening | Upgrade Kubernetes to avoid vulnerabilities | 19 | | | planned |
| System Hardening | Minimize host OS footprint (reduce attack surface) | 32 | | | planned |
| System Hardening | Using least-privilege identity and access management | 23, 32 | | | planned |
| System Hardening | Minimize external access to the network | 32, 36 | | | planned |
| System Hardening | Appropriately use kernel hardening tools such as AppArmor, seccomp | 32 | | | planned |
| Minimize Microservice Vulnerabilities | Use appropriate pod security standards | 33 | | | planned |
| Minimize Microservice Vulnerabilities | Manage kubernetes secrets | 07, 33 | | | planned |
| Minimize Microservice Vulnerabilities | Understand and implement isolation techniques (multi-tenancy, sandboxed containers, etc.) | 33 | | | planned |
| Minimize Microservice Vulnerabilities | Implement Pod-to-Pod encryption (Cilium, Istio) | 36 | | | planned |
| Supply Chain Security | Minimize base image footprint | 34 | | | planned |
| Supply Chain Security | Understand your supply chain (e.g. SBOM, CI/CD, artifact repositories) | 16, 34 | | | planned |
| Supply Chain Security | Secure your supply chain (permitted registries, sign and validate artifacts, etc.) | 34 | | | planned |
| Supply Chain Security | Perform static analysis of user workloads and container images (e.g. Kubesec, KubeLinter) | 34 | | | planned |
| Monitoring, Logging and Runtime Security | Perform behavioral analytics to detect malicious activities | 35 | | | planned |
| Monitoring, Logging and Runtime Security | Detect threats within physical infrastructure, apps, networks, data, users and workloads | 35 | | | planned |
| Monitoring, Logging and Runtime Security | Investigate and identify phases of attack and bad actors within the environment | 35 | | | planned |
| Monitoring, Logging and Runtime Security | Ensure immutability of containers at runtime | 35 | | | planned |
| Monitoring, Logging and Runtime Security | Use Kubernetes audit logs to monitor access | 35 | | | planned |

## KCSA

| Domain | Weight |
|---|---|
| Overview of Cloud Native Security | 14% |
| Kubernetes Cluster Component Security | 22% |
| Kubernetes Security Fundamentals | 22% |
| Kubernetes Threat Model | 16% |
| Platform Security | 16% |
| Compliance and Security Frameworks | 10% |

| Domain | Bullet (verbatim) | Chapter | Lab | Questions | Status |
|---|---|---|---|---|---|
| Overview of Cloud Native Security | The 4Cs of Cloud Native Security | 29 | | | planned |
| Overview of Cloud Native Security | Cloud Provider and Infrastructure Security | 29, 30 | | | planned |
| Overview of Cloud Native Security | Controls and Frameworks | 29 | | | planned |
| Overview of Cloud Native Security | Isolation Techniques | 33 | | | planned |
| Overview of Cloud Native Security | Artifact Repository and Image Security | 34 | | | planned |
| Overview of Cloud Native Security | Workload and Application Code Security | 33, 34 | | | planned |
| Kubernetes Cluster Component Security | API Server | 02, 30 | 02/T2, 02/T3 | ch02-q01, q06 | partly (02 explains its role; 30 secures it) |
| Kubernetes Cluster Component Security | Controller Manager | 02, 30 | 02/T3 | ch02-q05 | partly |
| Kubernetes Cluster Component Security | Scheduler | 02, 30 | 02/T4 | ch02-q02 | partly |
| Kubernetes Cluster Component Security | Kubelet | 02, 30 | | ch02-q03, q07 | partly |
| Kubernetes Cluster Component Security | Container Runtime | 01, 33 | | ch01-q04, q05 | partly |
| Kubernetes Cluster Component Security | KubeProxy | 02, 21 | P1 Q14 | | partly |
| Kubernetes Cluster Component Security | Pod | 04, 33 | 04/T1-T5 | ch04-q01, q02 | partly |
| Kubernetes Cluster Component Security | Etcd | 02, 20, 30 | 02/T2 | ch02-q01, q08 | partly |
| Kubernetes Cluster Component Security | Container Networking | 21, 36 | | | planned |
| Kubernetes Cluster Component Security | Client Security | 03, 30 | 03/b1 | ch02-q10; ch03-q08 | partly (03 covers kubeconfig; 30 secures it) |
| Kubernetes Cluster Component Security | Storage | 13, 22 | | | planned |
| Kubernetes Security Fundamentals | Pod Security Standards | 33 | | | planned |
| Kubernetes Security Fundamentals | Pod Security Admissions | 31, 33 | | | planned |
| Kubernetes Security Fundamentals | Authentication | 31 | | | planned |
| Kubernetes Security Fundamentals | Secrets | 07, 33 | 03/b2 C2 | | partly |
| Kubernetes Security Fundamentals | Isolation and Segmentation | 06, 33, 36 | | | planned |
| Kubernetes Security Fundamentals | Audit Logging | 35 | | | planned |
| Kubernetes Security Fundamentals | Network Policy | 21, 36 | | | planned |
| Kubernetes Threat Model | Kubernetes Trust Boundaries and Data Flow | 29 | | | planned |
| Kubernetes Threat Model | Persistence | 29, 35 | | | planned |
| Kubernetes Threat Model | Denial of Service | 10, 29 | | | planned |
| Kubernetes Threat Model | Malicious Code Execution and Compromised Applications in Containers | 29, 35 | | | planned |
| Kubernetes Threat Model | Attacker on the Network | 29, 36 | | | planned |
| Kubernetes Threat Model | Access to Sensitive Data | 29, 33 | | | planned |
| Kubernetes Threat Model | Privilege Escalation | 29, 33 | | | planned |
| Platform Security | Supply Chain Security | 34 | | | planned |
| Platform Security | Image Repository | 34 | | | planned |
| Platform Security | Observability | 15, 35 | | | planned |
| Platform Security | Service Mesh | 28, 36 | | | planned |
| Platform Security | PKI | 27, 30 | | | planned |
| Platform Security | Connectivity | 21, 36 | | | planned |
| Platform Security | Admission Control | 31 | | | planned |
| Compliance and Security Frameworks | Compliance Frameworks | 29 | | | planned |
| Compliance and Security Frameworks | Threat Modeling Frameworks | 29 | | | planned |
| Compliance and Security Frameworks | Supply Chain Compliance | 34 | | | planned |
| Compliance and Security Frameworks | Automation and Tooling | 30, 34 | | | planned |

## Gaps found and how they were closed

Mapping the verbatim bullets (2026-10-09) showed three CKAD bullets the chapter
plan did not cover well. `ROADMAP.md` now assigns each one; the rows above
already reflect it.

1. **"Define, build and modify container images"**: no chapter taught building
   images; Chapter 01 only explains them. Now in **Chapter 16**, renamed
   "Container images and application delivery" (Dockerfile, build, tag, push,
   changing an image), next to the CI/CD it feeds.
2. **"Understand API depreciations"**: only API groups and versions were covered
   (Chapter 02). Now in **Chapter 15**, "Developer observability and
   maintenance": the deprecation policy, finding deprecated `apiVersion`s, and
   migrating manifests.
3. **"Understand Application Security (SecurityContexts, Capabilities, etc.)"**
   sat only in Chapter 33 (Part IV), which CKAD readers may never reach. Now
   introduced in **Chapter 10** (`securityContext`, users, capabilities,
   read-only root filesystem); Chapter 33 keeps the hardening view.

## Supporting skills (not curriculum bullets)

The curricula do not list these, but every performance-based exam depends on
them. They are mapped here so their coverage stays visible.

| Skill | Chapter | Lab | Questions | Status |
|---|---|---|---|---|
| kubeconfig: create, switch, delete contexts; default namespace | 02, 03 | 03/b1; P1 Q1 | ch02-q10; ch03-q01, q08 | drafted |
| Discover resources and fields (`api-resources`, `explain`) | 02, 03 | 02/T5; 03/a A6; P1 Q12 | ch02-q11, q13; ch03-q12 | drafted |
| Selectors, JSONPath, and custom columns | 03 | 03/a A1-A3; 03/final Q2, Q6; P1 Q9 | ch03-q02, q06, q07, q13 | drafted |
| Labels and annotations from the command line | 03 | 03/a A4; 03/b2p P3; 03/final Q3; P1 Q7, Q8 | ch03-q10 | drafted |
| Imperative creation and generated manifests (`--dry-run=client -o yaml`) | 03, 04 | 03/a A5; 03/b2p; 03/final Q1, Q5; 04/T1; P1 Q2, Q10 | ch03-q03, q04, q09; ch04-q06, q12 | drafted |
| `kubectl wait`, `patch`, `set image`, `replace --force` | 03, 04 | 03/b2p P4; 03/final Q4; 04/T2; P1 Q3 | ch03-q11; ch04-q08 | drafted |
| `jq` and `yq` | 03 | 03/a A7 (optional) | ch03-q15 | drafted |
| Fast terminal: aliases, completion, `vim` | 03, 37 | | | partly |
| Working under time pressure, context per question | 03, 37 | 03/final; P1 (whole exam) | | partly |

## Curriculum revisions checked

Record, per exam, which curriculum file the mapping was checked against, so an
infrastructure change to `versions.env` can never silently change what the
book claims to teach.

| Exam | Curriculum file | Date checked | Source |
|---|---|---|---|
| KCNA | `KCNA_Curriculum.pdf` (4 domains: 44/28/16/12) | 2026-10-09 | cncf/curriculum, master |
| CKA | `CKA_Curriculum_v1.35.pdf` (5 domains: 25/15/20/10/30) | 2026-10-09 | cncf/curriculum, master |
| CKAD | `CKAD_Curriculum_v1.37.pdf` (5 domains: 20/20/15/25/20); a v1.35 file also exists | 2026-10-09 | cncf/curriculum, master |
| CKS | `CKS_Curriculum v1.34.pdf` (6 domains: 15/15/10/20/20/20) | 2026-10-09 | cncf/curriculum, master |
| KCSA | `KCSA Curriculum.pdf` (6 domains: 14/22/22/16/16/10) | 2026-10-09 | cncf/curriculum, master |

Note that KCNA's grouping changed from older study material: "Containerization"
is now part of Kubernetes Fundamentals, and "Networking", "Security",
"Troubleshooting", and "Storage" form Container Orchestration.

### Exam environment (checked when Chapter 03 was written)

From the Linux Foundation's published exam instructions: CKA and CKAD run 15 to 20 tasks in two hours on designated SSH hosts that have `kubectl` with the `k` alias and Bash completion, `yq`, `curl`, `wget`, and `man` pages; `jq` and `tmux` are not listed. The CKA environment was on Kubernetes v1.35 and the CKAD on v1.37 at that time. Chapter 03 teaches `jq` and `tmux` as conveniences only and `yq` as a tool that exists in the exam. Re-read the instructions before every edition.

## Kubernetes version

The book pins one minor version in `versions.env`. Re-check the version each
exam is currently written against before each edition. The curriculum files
above match the exam versions reported at the time this file was started (CKA
v1.35, CKAD v1.37, CKS v1.34), which is why v1.35 is the current pin.
