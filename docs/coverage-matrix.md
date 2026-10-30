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
  - `partly (gap: ...)`: every listed chapter is written, but they do not yet
    cover the whole bullet; the note says what is missing.
  - `drafted`: every listed chapter is written and its lab passes CI on a real
    cluster, but it has not been reviewed against the curriculum or completed by
    a beta reader.
  - `verified`: drafted, plus reviewed and completed by a beta reader.
- Re-check every exam against the current PDFs before each edition, and record
  the check in "Curriculum revisions checked".

## KCNA

| Domain | Weight |
| --- | --- |
| Kubernetes Fundamentals | 44% |
| Container Orchestration | 28% |
| Cloud Native Application Delivery | 16% |
| Cloud Native Architecture | 12% |

The KCNA curriculum lists topics, not tasks, so each row is broad. Chapters
01 to 06 and 28 are the KCNA core; the rest go deeper than the exam needs.
The KCNA practice exam (`mock-exams/kcna`) covers every domain with the
curriculum's weights: 26, 17, 10, and 7 of its 60 questions.

| Domain | Bullet (verbatim) | Chapter | Lab | Questions | Status |
| --- | --- | --- | --- | --- | --- |
| Kubernetes Fundamentals | Kubernetes Core Concepts | 02, 04, 05, 06 | 02/T1-T5, 04/T1-T5, 05/T1-T6, 06/T1-T5; P1 Q15, Q18 | ch02-q01..q05, q08; ch04-q01, q02, q04; ch05-q01..q03; ch06-q01..q05 | drafted |
| Kubernetes Fundamentals | Administration | 03, 06, 18, 19, 20 | 03/a, 03/b1, 03/b2p; 06/T2; 18/T1–T5; 19/T1–T5; 20/T1–T4; P1 Q15 | ch02-q10; ch03-q01, q08; ch06-q09; ch18-q10; ch19-q06; ch20-q01 | drafted |
| Kubernetes Fundamentals | Scheduling | 02, 17 | 02/T4; 17/T1–T5 | ch02-q02, q12; ch17-q01–q07 | drafted |
| Kubernetes Fundamentals | Containerization | 01, 04 | 04/T1, 04/T5 | ch01-q04..q06; ch04-q01 | drafted |
| Container Orchestration | Networking | 11, 21, 26 | 11/T1–T5; 21/T1–T5 | ch11-q01–q11; ch21-q01–q11 | drafted |
| Container Orchestration | Security | 23, 29, 31, 33 | 03/b3; 23/T1–T5; 33/T1–T5 | ch03-q05; ch23-q01–q07; ch29-q01, q02, q12; ch33-q01 | drafted |
| Container Orchestration | Troubleshooting | 04, 26 | 04/T2; 26/T1–T5; P1 Q3 | ch04-q03, q11; ch26-q01–q11 | drafted |
| Container Orchestration | Storage | 13 | 13/T1–T5 | ch13-q01–q03, q05 | drafted |
| Cloud Native Application Delivery | Application Delivery | 14, 16 | 16/T1–T5 | ch16-q06, q08–q11 | drafted |
| Cloud Native Application Delivery | Debugging | 04, 15, 26 | 04/T2, 04/T3; 15/T1–T2; 26/T1–T5; P1 Q4 | ch04-q03, q11; ch15-q03; ch26-q01, q07, q10 | drafted |
| Cloud Native Architecture | Observability | 01, 15, 28 | 15/T4 | ch01-q10; ch15-q05, q06; ch28-q01 | drafted |
| Cloud Native Architecture | Cloud Native Ecosystem and Principles | 01, 28 | 01 and 28 exploration exercises | ch01-q07..q11, q15; ch28-q01..q08 | drafted |
| Cloud Native Architecture | Could Native Community and Collaboration | 01, 28 | 01 and 28 exploration exercises | ch01-q02, q03, q12..q14; ch28-q09..q15 | drafted |

## CKA

| Domain | Weight |
| --- | --- |
| Storage | 10% |
| Troubleshooting | 30% |
| Workloads and Scheduling | 15% |
| Servicing and Networking | 20% |
| Cluster Architecture, Installation and Configuration | 25% |

The CKA simulator (`mock-exams/cka`, on the Tier 2 VMs) covers every domain in one
timed exam, at the curriculum's weights: Cluster Architecture Q1–Q4 (25%),
Workloads and Scheduling Q5–Q7 (15%), Services and Networking Q8–Q11 (20%),
Storage Q12–Q13 (10%), Troubleshooting Q14–Q18 (30%).

| Domain | Bullet (verbatim) | Chapter | Lab | Questions | Status |
| --- | --- | --- | --- | --- | --- |
| Storage | Implement storage classes and dynamic volume provisioning | 13, 22 | 13/T1, T5; 22/T1, T4 | ch13-q04, q10; ch22-q01–q04, q08 | drafted |
| Storage | Configure volume types, access modes and reclaim policies | 13, 22 | 13/T3–T5; 22/T2–T3; P3 Q9 | ch13-q01, q03, q05, q07; ch22-q05, q07, q10 | drafted |
| Storage | Manage persistent volumes and persistent volume claims | 13 | 13/T1–T3; P3 Q9 | ch13-q02, q08, q11 | drafted |
| Troubleshooting | Troubleshoot clusters and nodes | 02, 27 | 02/T1, 02/T3; 27/T1–T2; P3 Q15 | ch02-q03, q07; ch27-q01–q03, q10 | drafted |
| Troubleshooting | Troubleshoot cluster components | 02, 27 | 02/T2, 02/T3; 27/T3–T5; P1 Q14; P3 Q2, Q16 | ch02-q01..q05, q07; ch27-q04–q09, q11, q12 | drafted |
| Troubleshooting | Monitor cluster and application resource usage | 10, 15, 25 | 25/T3 | ch15-q05, q06; ch25-q03, q11 | drafted |
| Troubleshooting | Manage and evaluate container output streams | 04, 15, 26 | 04/T3; 15/T1; 26/T1 | ch04-q11, ch15-q01, q02, q04; ch26-q01 | drafted |
| Troubleshooting | Troubleshoot services and networking | 11, 21, 26 | 11/T5; 26/T2–T5; P3 Q5, Q14 | ch11-q02, q11; ch26-q02–q06 | drafted |
| Workloads and Scheduling | Understand application deployments and how to perform rolling update and rollbacks | 05 | 05/T1-T6; P1 Q15-Q17 | ch05-q04..q08, q10..q14 | drafted |
| Workloads and Scheduling | Use ConfigMaps and Secrets to configure applications | 03, 07 | 03/b2 C1, C2; 07/T1–T5; P1 Q11 | ch07-q01–q03, q08–q11 | drafted |
| Workloads and Scheduling | Configure workload autoscaling | 25 | 25/T1–T5; P3 Q13 | ch25-q01–q03, q06, q07, q08, q09, q10, q11 | drafted (VPA and cluster autoscaler described, not installed) |
| Workloads and Scheduling | Understand the primitives used to create robust, self-healing, application deployments | 04, 05, 10 | 04/T5; 05/T1, T2, T5; P1 Q18 | ch04-q04, q05; ch05-q01..q03, q06, q07 | drafted |
| Workloads and Scheduling | Configure Pod admission and scheduling (limits, node affinity, etc.) | 04, 06, 10, 17 | 04/T4; 06/T5; 17/T1–T2; P1 Q5; P3 Q1 | ch04-q07, q09; ch06-q12; ch17-q02–q05 | drafted |
| Servicing and Networking | Understand connectivity between Pods | 11, 21 | 21/T1–T2; P3 Q8 | ch21-q01, q02 | drafted |
| Servicing and Networking | Define and enforce Network Policies | 21, 36 | 21/T3–T4; 36/T1–T3; P3 Q7 | ch21-q03–q06, q08, q09; ch36-q01–q05, q10, q11 | drafted |
| Servicing and Networking | Use ClusterIP, NodePort, LoadBalancer service types and endpoints | 03, 11 | 03/b2 C5; 11/T1–T2; P1 Q11 | ch11-q01–q03, q08; LoadBalancer described only | drafted |
| Servicing and Networking | Use the Gateway API to manage Ingress traffic | 12 | 12/T4–T5 | ch12-q05, q07, q10, q11 | drafted (checked against the API server; no controller runs) |
| Servicing and Networking | Know how to use Ingress controllers and Ingress resources | 12 | 12/T1–T3, T6 | ch12-q02–q04, q08, q12, q13 | drafted (Traefik installed with Helm; requests sent through it) |
| Servicing and Networking | Understand and use CoreDNS | 11, 21 | 11/T3–T4; 21/T2 | ch11-q05–q07; ch21-q07, q11 | drafted |
| Cluster Architecture, Installation and Configuration | Manage role based access control (RBAC) | 03, 23 | 03/b3; 23/T1–T2, T5; P3 Q10, Q11 | ch03-q05, q14; ch23-q02–q04, q06, q07 | drafted |
| Cluster Architecture, Installation and Configuration | Prepare underlying infrastructure for installing a Kubernetes cluster | 18 | 18 walkthrough (prepared on the `prereqs` snapshot) | ch18-q03, q04, q05, q13 | drafted (the reader inspects the preparation; `bootstrap-os.sh` and `bootstrap-tools.sh` script it) |
| Cluster Architecture, Installation and Configuration | Create and manage Kubernetes clusters using kubeadm | 18 | 18/T1–T5; P3 Q3 | ch18-q01, q02, q06, q07, q10–q12, q14 | drafted (verified by hand on the Tier 2 VMs) |
| Cluster Architecture, Installation and Configuration | Manage the lifecycle of Kubernetes clusters | 19, 20 | 19/T1–T5; 20/T1–T4; P3 Q4, Q6 | ch19-q01–q09, q11–q13; ch20-q01–q12 | drafted |
| Cluster Architecture, Installation and Configuration | Implement and configure a highly-available control plane | 18 | | ch18-q08, q09 | partly (gap: concepts and flags only; a lab needs a load balancer and more control plane nodes than Tier 2 has) |
| Cluster Architecture, Installation and Configuration | Use Helm and Kustomize to install cluster components | 12, 14 | 12/T6; 14/T1–T4 | ch12-q13; ch14-q01, q06, q11 | drafted (12 installs the Ingress controller with Helm) |
| Cluster Architecture, Installation and Configuration | Understand extension interfaces (CNI, CSI, CRI, etc.) | 01, 22, 24 | 21/T1–T2; 22/T5; 24/T5 | ch01-q04, q05; ch22-q01–q03; ch24-q03, q04 | drafted |
| Cluster Architecture, Installation and Configuration | Understand CRDs, install and configure operators | 24 | 24/T1–T4, T6; P3 Q12 | ch24-q01, q02, q05–q07, q12, q13 | drafted (cert-manager installed with Helm and configured through its custom resources) |

## CKAD

| Domain | Weight |
| --- | --- |
| Application Design and Build | 20% |
| Application Deployment | 20% |
| Application Observability and Maintenance | 15% |
| Application Environment, Configuration and Security | 25% |
| Services and Networking | 20% |

The CKAD simulator (`mock-exams/ckad`) covers every domain in one timed exam.
By domain: Design and Build Q1–Q4 (20%), Deployment Q5–Q8 (21%), Observability
and Maintenance Q9–Q12 (15%), Environment, Configuration and Security Q13–Q17
(25%), Services and Networking Q18–Q20 (19%).

| Domain | Bullet (verbatim) | Chapter | Lab | Questions | Status |
| --- | --- | --- | --- | --- | --- |
| Application Design and Build | Define, build and modify container images | 01, 16 | 16/T1 | ch01-q05; ch16-q01–q03 | drafted |
| Application Design and Build | Choose and use the right workload resource (Deployment, DaemonSet, CronJob, etc.) | 05, 08, 09, 13 | 05/T1; 08/T1–T5; 09/T6; 13/T6 | ch05-q09, ch08-q01–q07; ch09-q12, q13; ch13-q12, q13 | drafted |
| Application Design and Build | Understand multi-container Pod design patterns (e.g. sidecar, init and others) | 04, 09 | 09/T1–T5; P1 Q10 | ch04-q02, ch09-q01–q11 | drafted |
| Application Design and Build | Utilize persistent and ephemeral volumes | 13 | 13/T1–T2, T4 | ch13-q01, q06, q09 | drafted |
| Application Deployment | Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary) | 05, 16 | 05/T5; 16/T3–T4, T6 | ch05-q06, q13; ch16-q07, q10–q13 | drafted (blue/green in the lab; canary by replica ratio in the walkthrough) |
| Application Deployment | Understand Deployments and how to perform rolling updates | 05 | 05/T1-T6; P1 Q15-Q17 | ch05-q04..q08, q10..q14 | drafted |
| Application Deployment | Use the Helm package manager to deploy existing packages | 14 | 14/T1–T3, T5 | ch14-q02–q04, q08–q10 | drafted |
| Application Deployment | Kustomize | 14 | 14/T4 | ch14-q05, q06, q11 | drafted |
| Application Observability and Maintenance | Understand API depreciations | 02, 15 | 02/T5; 15/T5; P1 Q12 | ch02-q09, q11; ch15-q07, q11 | drafted |
| Application Observability and Maintenance | Implement probes and health checks | 10 | 10/T1–T2 | ch02-q13 (explain only), ch10-q01, q02, q08 | drafted |
| Application Observability and Maintenance | Use built-in CLI tools to monitor Kubernetes applications | 03, 06, 15 | 03/a A1-A4; 03/final Q2, Q6; 06/T1, T4; P1 Q9 | ch03-q06, q07, q11; ch06-q08, q10 | drafted |
| Application Observability and Maintenance | Utilize container logs | 04, 15 | 04/T3; 15/T1, T3; P1 Q4 | ch04-q11, ch15-q01, q02, q04, q08 | drafted |
| Application Observability and Maintenance | Debugging in Kubernetes | 04, 15, 26 | 04/T2; 15/T1–T2; 26/T1–T5; P1 Q3, Q6 | ch04-q03, q11; ch15-q03, q08, q09; ch26-q01, q05, q07, q10 | drafted |
| Application Environment, Configuration and Security | Discover and use resources that extend Kubernetes (CRD, Operators) | 03, 24 | 03/a A6; 24/T2–T4; P1 Q12 | ch03-q12; ch24-q06, q07 | drafted |
| Application Environment, Configuration and Security | Understand authentication, authorization and admission control | 03, 23, 31 | 03/b3; 23/T1–T5; 31/T1–T4 | ch03-q05, q14; ch23-q01, q06; ch31-q01–q04, q06, q10 | drafted |
| Application Environment, Configuration and Security | Understand requests, limits, quotas | 04, 10 | 04/T4; 10/T3–T4, T6; P1 Q5 | ch04-q07, q09; ch10-q04, q05, q12, q13 | drafted |
| Application Environment, Configuration and Security | Define resource requirements | 04, 10 | 04/T4; 10/T3–T4; P1 Q5 | ch04-q07, q09; ch10-q03, q04, q09, q10 | drafted |
| Application Environment, Configuration and Security | Understand ConfigMaps | 03, 07 | 03/b2 C1; 07/T1, T3–T5; P1 Q11 | ch07-q02, q03, q06, q08 | drafted |
| Application Environment, Configuration and Security | Create & consume Secrets | 03, 07 | 03/b2 C2; 07/T2–T5; P1 Q11 | ch07-q01, q05, q09, q11 | drafted |
| Application Environment, Configuration and Security | Understand ServiceAccounts | 03, 23 | 03/b2 C3; 23/T3–T4 | ch23-q05, q10 | drafted |
| Application Environment, Configuration and Security | Understand Application Security (SecurityContexts, Capabilities, etc.) | 10, 33 | 10/T5; 33/T2–T3 | ch10-q06, q07, q11; ch33-q06 | drafted |
| Services and Networking | Demonstrate basic understanding of NetworkPolicies | 21 | 21/T3–T4 | ch21-q03–q06, q08, q09 | drafted |
| Services and Networking | Provide and troubleshoot access to applications via services | 03, 11, 26 | 03/b2 C5; 11/T1–T5; 26/T2–T3; P1 Q11; P3 Q14 | ch11-q01, q04, q06, q08–q11; ch26-q02–q05, q08, q11 | drafted |
| Services and Networking | Use Ingress rules to expose applications | 12 | 12/T1–T3 | ch12-q02–q04, q08 | drafted |

## CKS

| Domain | Weight |
| --- | --- |
| Cluster Setup | 15% |
| Cluster Hardening | 15% |
| System Hardening | 10% |
| Minimize Microservice Vulnerabilities | 20% |
| Supply Chain Security | 20% |
| Monitoring, Logging and Runtime Security | 20% |

| Domain | Bullet (verbatim) | Chapter | Lab | Questions | Status |
| --- | --- | --- | --- | --- | --- |
| Cluster Setup | Use Network security policies to restrict cluster level access | 21, 36 | 21/T3–T4; 36/T1–T3 | ch21-q03–q06, q08, q09; ch36-q01–q06, q10, q11 | drafted |
| Cluster Setup | Use CIS benchmark to review the security configuration of Kubernetes components (etcd, kubelet, kubedns, kubeapi) | 30 | 30/T1–T2 | ch30-q01–q04, q11, q13 | drafted |
| Cluster Setup | Properly set up Ingress objects with TLS | 12, 30 | 12/T2 | ch12-q06, q09 | drafted |
| Cluster Setup | Protect node metadata and endpoints | 30, 36 | 30/T3, 30/T5 | ch30-q05, q10 | drafted |
| Cluster Setup | Verify platform binaries before deploying | 30 | 30/T4 | ch30-q09 | drafted |
| Cluster Hardening | Use Role Based Access Controls to minimize exposure | 23, 31 | 23/T1–T2, T5; 31/T4 | ch23-q02–q04, q07–q09; ch31-q03, q04, q13 | drafted |
| Cluster Hardening | Exercise caution in using service accounts e.g. disable defaults, minimize permissions on newly created ones | 23, 31 | 23/T3–T4; 31/T3 | ch23-q05, q06, q08, q10, q11; ch31-q10 | drafted |
| Cluster Hardening | Restrict access to Kubernetes API | 30, 31 | 30/T3; 31/T1–T5 | ch30-q06, q08, q12 | drafted |
| Cluster Hardening | Upgrade Kubernetes to avoid vulnerabilities | 19 | 19/T1–T4 | ch19-q01, q02, q10 | drafted |
| System Hardening | Minimize host OS footprint (reduce attack surface) | 32 | | | planned |
| System Hardening | Using least-privilege identity and access management | 23, 32 | | | planned |
| System Hardening | Minimize external access to the network | 32, 36 | | | planned |
| System Hardening | Appropriately use kernel hardening tools such as AppArmor, seccomp | 32 | | | planned |
| Minimize Microservice Vulnerabilities | Use appropriate pod security standards | 33 | 33/T1–T2 | ch33-q01–q06 | drafted |
| Minimize Microservice Vulnerabilities | Manage kubernetes secrets | 07, 33 | 07/T2; 33/T3–T4 | ch07-q01, q09; ch33-q07–q10 | drafted |
| Minimize Microservice Vulnerabilities | Understand and implement isolation techniques (multi-tenancy, sandboxed containers, etc.) | 33 | 33/T5 | ch33-q11, q12 | drafted |
| Minimize Microservice Vulnerabilities | Implement Pod-to-Pod encryption (Cilium, Istio) | 36 | | ch36-q07 (concept) | partly (encryption explained; no mesh or CNI encryption lab) |
| Supply Chain Security | Minimize base image footprint | 34 | | | partly (gap: 34 is written but covers digests, not base image size; add distroless, multi-stage and scratch images to 34 or 16) |
| Supply Chain Security | Understand your supply chain (e.g. SBOM, CI/CD, artifact repositories) | 16, 34 | 34/T1–T3 | ch16-q06; ch34-q01–q03, q08 | partly (16 covers CI/CD and GitOps; 34 covers SBOMs and artifacts) |
| Supply Chain Security | Secure your supply chain (permitted registries, sign and validate artifacts, etc.) | 34 | 34/T1–T2 | ch34-q04, q05, q07, q10 | partly (34 covers registries and digests; signature verification is a concept) |
| Supply Chain Security | Perform static analysis of user workloads and container images (e.g. Kubesec, KubeLinter) | 34 | | ch34-q02 (concept) | partly (scanning explained; no scanner lab) |
| Monitoring, Logging and Runtime Security | Perform behavioral analytics to detect malicious activities | 35 | | | planned |
| Monitoring, Logging and Runtime Security | Detect threats within physical infrastructure, apps, networks, data, users and workloads | 35 | | | planned |
| Monitoring, Logging and Runtime Security | Investigate and identify phases of attack and bad actors within the environment | 35 | | | planned |
| Monitoring, Logging and Runtime Security | Ensure immutability of containers at runtime | 35 | | | planned |
| Monitoring, Logging and Runtime Security | Use Kubernetes audit logs to monitor access | 35 | | | planned |

## KCSA

| Domain | Weight |
| --- | --- |
| Overview of Cloud Native Security | 14% |
| Kubernetes Cluster Component Security | 22% |
| Kubernetes Security Fundamentals | 22% |
| Kubernetes Threat Model | 16% |
| Platform Security | 16% |
| Compliance and Security Frameworks | 10% |

| Domain | Bullet (verbatim) | Chapter | Lab | Questions | Status |
| --- | --- | --- | --- | --- | --- |
| Overview of Cloud Native Security | The 4Cs of Cloud Native Security | 29 | 29 exploration exercise | ch29-q01–q03 | drafted |
| Overview of Cloud Native Security | Cloud Provider and Infrastructure Security | 29, 30 | 30/T5 | ch29-q04, q05; ch30-q10 | drafted |
| Overview of Cloud Native Security | Controls and Frameworks | 29 | 29 exploration exercise | ch29-q10, q11 | drafted |
| Overview of Cloud Native Security | Isolation Techniques | 33 | 33/T5 | ch33-q11, q12 | drafted |
| Overview of Cloud Native Security | Artifact Repository and Image Security | 34 | 34/T1–T3 | ch34-q01, q09, q11, q12 | drafted |
| Overview of Cloud Native Security | Workload and Application Code Security | 33, 34 | 33/T2–T3 | ch33-q06, q07 | drafted |
| Kubernetes Cluster Component Security | API Server | 02, 30 | 02/T2, 02/T3; 30/T2 | ch02-q01, q06; ch30-q03, q06, q08 | drafted |
| Kubernetes Cluster Component Security | Controller Manager | 02, 30 | 02/T3; 30/T2 | ch02-q05 | drafted |
| Cluster Component Security | Scheduler | 02, 30 | 02/T4; 17/T5; 30/T2 | ch02-q02; ch17-q01, q06, q07; ch30-q13 | drafted |
| Kubernetes Cluster Component Security | Kubelet | 02, 30 | 30/T1, 30/T3 | ch02-q03, q07; ch30-q05, q11 | drafted |
| Kubernetes Cluster Component Security | Container Runtime | 01, 33 | 33/T5 | ch01-q04, q05; ch33-q11, q12 | drafted |
| Kubernetes Cluster Component Security | KubeProxy | 02, 21 | P1 Q14 | | partly |
| Kubernetes Cluster Component Security | Pod | 04, 33 | 04/T1-T5; 33/T2–T3 | ch04-q01, q02; ch33-q06 | drafted |
| Kubernetes Cluster Component Security | Etcd | 02, 20, 30, 33 | 02/T2; 20/T1–T4; 33/T4 | ch02-q01, q08; ch30-q04 | drafted |
| Kubernetes Cluster Component Security | Container Networking | 21, 36 | 21/T1–T2 | ch21-q01, q02 | partly (36 planned) |
| Kubernetes Cluster Component Security | Client Security | 03, 30 | 03/b1 | ch02-q10; ch03-q08; ch30-q07 | drafted |
| Kubernetes Cluster Component Security | Storage | 13, 22, 33, 36 | 13/T5; 22/T2; 33/T4 | ch13-q05; ch22-q07; ch33-q09, q10; ch36-q09 | drafted |
| Kubernetes Security Fundamentals | Pod Security Standards | 33 | 33/T1–T2 | ch33-q01–q06 | drafted |
| Kubernetes Security Fundamentals | Pod Security Admissions | 31, 33 | 31/T2; 33/T1–T2 | ch31-q08, q09, q12; ch33-q03–q05 | drafted |
| Kubernetes Security Fundamentals | Authentication | 31 | 31/T3 | ch31-q01, q02, q10, q13 | drafted |
| Kubernetes Security Fundamentals | Secrets | 07, 33 | 03/b2 C2; 33/T3–T4 | ch33-q07–q10 | drafted |
| Kubernetes Security Fundamentals | Isolation and Segmentation | 06, 33, 36 | 06/T2; 33/T5; 36/T1–T3 | ch06-q02; ch33-q11 | drafted |
| Kubernetes Security Fundamentals | Audit Logging | 35 | | | planned |
| Kubernetes Security Fundamentals | Network Policy | 21, 36 | 21/T3–T4; 36/T1–T3 | ch21-q03–q06, q08, q09; ch36-q01–q05, q10, q11 | drafted |
| Kubernetes Threat Model | Kubernetes Trust Boundaries and Data Flow | 29 | 29 exploration exercise | ch29-q13 | drafted |
| Kubernetes Threat Model | Persistence | 29, 35 | | ch29-q06, q08 | partly (29 drafted; 35 planned) |
| Kubernetes Threat Model | Denial of Service | 10, 29 | 10/T6 | | drafted |
| Kubernetes Threat Model | Malicious Code Execution and Compromised Applications in Containers | 29, 35 | | ch29-q12 | partly (29 drafted; 35 planned) |
| Kubernetes Threat Model | Attacker on the Network | 29, 36 | 36/T1–T4 | ch29-q04 | drafted |
| Kubernetes Threat Model | Access to Sensitive Data | 29, 33 | 33/T3–T4 | ch29-q07; ch33-q07–q10 | drafted |
| Kubernetes Threat Model | Privilege Escalation | 29, 33 | 33/T1–T2 | ch29-q07, q08; ch33-q02, q06 | drafted |
| Platform Security | Supply Chain Security | 34 | 34/T1–T3 | ch34-q01–q12 | drafted |
| Platform Security | Image Repository | 34 | 34/T1–T2 | ch34-q10 | partly |
| Platform Security | Observability | 15, 35 | | | planned |
| Platform Security | Service Mesh | 28, 36 | | ch28-q01–q04; ch36-q07 | drafted (concepts only, no mesh installed) |
| Platform Security | PKI | 18, 27, 30 | 27/T4–T5 | ch18-q06, q07; ch27-q07–q09, q11; ch30-q07 | drafted |
| Platform Security | Connectivity | 21, 36 | 21/T3–T4; 36/T1–T4 | ch21-q01–q05; ch36-q03–q08, q12 | drafted |
| Platform Security | Admission Control | 31 | 31/T1–T2, T4 | ch31-q05–q07, q11 | drafted |
| Compliance and Security Frameworks | Compliance Frameworks | 29 | | ch29-q11 | drafted |
| Compliance and Security Frameworks | Threat Modeling Frameworks | 29 | 29 exploration exercise | ch29-q09 | drafted |
| Compliance and Security Frameworks | Supply Chain Compliance | 34 | 34/T1–T3 | ch34-q03–q05, q08 | partly (SBOMs, signing and provenance described; compliance frameworks come with 29) |
| Compliance and Security Frameworks | Automation and Tooling | 30, 34 | 30/T1 | ch29-q10; ch30-q02 | drafted |

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

### Open gaps in written chapters (reviewed 2026-10-23)

A review of every KCNA, CKA, and CKAD row after Part III found these bullets
marked `partly (gap: ...)`: the chapters exist, but no hands-on work covers the
whole bullet yet. The three CKAD gaps, the two Ingress and Helm gaps, and the operator gap were closed the same day; only the highly available control plane stays conceptual.

| Exam | Bullet | Planned fix |
| --- | --- | --- |
| CKAD | Choose and use the right workload resource | Closed 2026-10-23: a StatefulSet with a claim per replica (13/T6) and a DaemonSet node agent (09/T6) |
| CKAD | Requests, limits, quotas | Closed 2026-10-23: a ResourceQuota and a LimitRange, and a Pod that runs with its defaults (10/T6) |
| CKAD | Deployment strategies (blue/green, canary) | Closed 2026-10-23: a blue/green switch (16/T6) and a canary by replica ratio in Chapter 16's walkthrough |
| CKA | Ingress controllers | Closed 2026-10-23: Traefik installed with Helm at a pinned chart version, and requests routed through it (12/T6) |
| CKA | Helm and Kustomize to install cluster components | Closed 2026-10-23 by the same install (12/T6) |
| CKA | CRDs and operators | Closed 2026-10-23: cert-manager installed with Helm, issuing and re-issuing a certificate (24/T6) |
| CKA | Highly available control plane | Stays conceptual: a real one needs a load balancer and more control plane nodes than the Tier 2 VMs provide |

## Supporting skills (not curriculum bullets)

The curricula do not list these, but every performance-based exam depends on
them. They are mapped here so their coverage stays visible.

| Skill | Chapter | Lab | Questions | Status |
| --- | --- | --- | --- | --- |
| kubeconfig: create, switch, delete contexts; default namespace | 02, 03 | 03/b1; P1 Q1 | ch02-q10; ch03-q01, q08 | drafted |
| Discover resources and fields (`api-resources`, `explain`) | 02, 03 | 02/T5; 03/a A6; P1 Q12 | ch02-q11, q13; ch03-q12 | drafted |
| Selectors (label and field), JSONPath, and custom columns | 03, 06 | 03/a A1-A3; 03/final Q2, Q6; 06/T1, T4; P1 Q9 | ch03-q02, q06, q07, q13; ch06-q04, q08, q10, q13 | drafted |
| Labels and annotations from the command line | 03, 06 | 03/a A4; 03/b2p P3; 03/final Q3; 06/T2, T3; P1 Q7, Q8, Q18 | ch03-q10; ch06-q03, q05, q07, q11 | drafted |
| Imperative creation and generated manifests (`--dry-run=client -o yaml`) | 03, 04 | 03/a A5; 03/b2p; 03/final Q1, Q5; 04/T1; P1 Q2, Q10 | ch03-q03, q04, q09; ch04-q06, q12 | drafted |
| `kubectl wait`, `patch`, `set image`, `replace --force` | 03, 04 | 03/b2p P4; 03/final Q4; 04/T2; P1 Q3 | ch03-q11; ch04-q08 | drafted |
| `jq` and `yq` | 03 | 03/a A7 (optional) | ch03-q15 | drafted |
| Fast terminal: aliases, completion, `vim` | 03, 37 | 37 drills | ch37-q01, q07, q08 | partly (37 drills the habits; setup is in 03) |
| Working under time pressure, context per question | 03, 37 | 03/final; 37 drills; P1 (whole exam) | ch37-q10 | partly |
| Finding answers in the allowed documentation, `explain`, and `--help` | 38 | 38 exploration exercise | ch38-q01–q12 | drafted |
| Exam logistics: booking, check-in, the exam environment, time strategy, study plans | 39 | 39 planning exercise | ch39-q01–q13 | drafted |

## Curriculum revisions checked

Record, per exam, which curriculum file the mapping was checked against, so an
infrastructure change to `versions.env` can never silently change what the
book claims to teach.

| Exam | Curriculum file | Date checked | Source |
| --- | --- | --- | --- |
| KCNA | `KCNA_Curriculum.pdf` (4 domains: 44/28/16/12) | 2026-10-09 | cncf/curriculum, master |
| CKA | `CKA_Curriculum_v1.37.pdf` (5 domains: 25/15/20/10/30); byte-identical to the v1.35 file the mapping was first checked against | 2026-10-23 | cncf/curriculum, master |
| CKAD | `CKAD_Curriculum_v1.37.pdf` (5 domains: 20/20/15/25/20); a v1.35 file also exists | 2026-10-09 | cncf/curriculum, master |
| CKS | `CKS_Curriculum v1.34.pdf` (6 domains: 15/15/10/20/20/20) | 2026-10-09 | cncf/curriculum, master |
| KCSA | `KCSA Curriculum.pdf` (6 domains: 14/22/22/16/16/10) | 2026-10-09 | cncf/curriculum, master |

Note that KCNA's grouping changed from older study material: "Containerization"
is now part of Kubernetes Fundamentals, and "Networking", "Security",
"Troubleshooting", and "Storage" form Container Orchestration.

### Exam environment (checked when Chapter 03 was written)

From the Linux Foundation's published exam instructions: CKA and CKAD run 15 to 20 tasks in two hours on designated SSH hosts that have `kubectl` with the `k` alias and Bash completion, `yq`, `curl`, `wget`, and `man` pages; `jq` and `tmux` are not listed. The CKA environment was on Kubernetes v1.35 and the CKAD on v1.37 at that time; on 2026-10-23 both ran v1.37, and the instructions and the allowed-resources page (Kubernetes docs and blog, Helm docs, and for the CKA the Gateway API docs) were re-read for Chapters 03 and 38. Chapter 03 teaches `jq` and `tmux` as conveniences only and `yq` as a tool that exists in the exam. Re-read the instructions before every edition.

## Kubernetes version

The book pins one minor version in `versions.env`. Re-check the version each
exam is currently written against before each edition. The curriculum files
above match the exam versions reported at the time this file was started (CKA
v1.35, CKAD v1.37, CKS v1.34). On 2026-10-23 the CKA and the CKAD both ran
v1.37, and the book moved its pin from v1.35 to v1.37.0 (kind v0.33.0 ships
node images up to v1.37.0); the VMs' `cluster-prev` snapshot moved to v1.36.5.
