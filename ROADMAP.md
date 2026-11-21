# ROADMAP: The Kubestronaut Textbook

A hands-on textbook covering everything needed for the six certifications that make up **Kubestronaut**: **KCNA, KCSA, CKAD, CKA, CKS**, and the **CKNE** (Certified Kubernetes Network Engineer), which joined the program in 2026.

- **Audience:** readers who already know Linux, basic web development, and containers. Networking is not assumed: Part V teaches it from zero for the CKNE Parts.
- **Format:** one Markdown file per chapter, plus setup files for each chapter's lab environment.
- **Labs:** KodeKloud-style for learning (one task at a time, a check after each); killer.sh-style for the mock exam that closes each Part, and for short timed warm-ups inside chapters (weighted questions, a context per question, scored together against a pass mark). All repeatable and resettable with one command.
- **Assessment:** end-of-chapter questions in every chapter, plus a mock exam per certification.

> **Before locking the outline:** verify each certification's current curriculum (domains, weights, Kubernetes version) on the CNCF/Linux Foundation curriculum repos. Update `docs/coverage-matrix.md` (see §6) whenever they change.
> **CKNE checked (2026-11-17):** the five domains, their weights, and all 22 competencies match `cncf/curriculum/CKNE_Curriculum.pdf` word for word, and are in `docs/coverage-matrix.md`. The LF FAQ confirms 2 hours, a 67% pass mark, one free retake when eligible, 2-year validity, and English only; the allowed documentation is `kubernetes.io/docs`, `kubernetes.io/blog`, `docs.cilium.io`, and `istio.io/latest/docs`. The number of tasks, the Kubernetes/Cilium/Istio versions, and the price are not published; treat third-party figures (15 to 20 tasks, v1.37, US$445) as unconfirmed.
> **Already checked (2026-10-09):** all five curricula (KCNA, CKA v1.35, CKAD v1.37, CKS v1.34, KCSA) are transcribed verbatim into `docs/coverage-matrix.md` from the `cncf/curriculum` PDFs. The mapping found three gaps in the chapter plan, now closed: building container images (Chapter 16), API deprecations (Chapter 15), and `securityContext` and capabilities for CKAD readers (Chapter 10, with the hardening view still in 33).

---

## 1. Guiding principles

1. **Teach by topic, tag by exam.** The five exams overlap heavily. Chapters are organized by subject; each chapter declares which exams it serves.
2. **Every lab is disposable.** A reader can break anything and be back at the starting state in under a minute.
3. **Every lab is verifiable.** Each task has an automated check, so readers get instant PASS/FAIL feedback.
4. **Every lab is tested in CI.** If the reference solution does not pass `verify.sh` in CI, the chapter does not merge.
5. **Speed matters.** The performance-based exams are timed. Labs teach imperative `kubectl`, docs navigation, and time budgeting from Part I onward, not just in the exam-prep part.
6. **One version pin.** The Kubernetes version and all tool versions live in a single `versions.env`.

---

## 2. Repository layout

```text
kubestronaut-book/
├── ROADMAP.md
├── versions.env                 # K8s version + pinned tool versions
├── Makefile                     # make lab / reset / verify / solve CH=07
├── docs/
│   ├── style-guide.md
│   ├── chapter-template.md
│   ├── coverage-matrix.md       # every curriculum bullet -> chapter + lab
│   └── lab-authoring.md         # conventions for setup/reset/verify scripts
├── tools/
│   ├── lib.sh                   # shared shell helpers (log, assert, wait)
│   ├── render-questions.py      # questions/*.yaml -> chapter markdown
│   └── lint/                    # markdown + shellcheck + yamllint config
├── envs/
│   ├── netlab/                  # Tier 0 netlab container (Part V): Dockerfile + rootfs helpers
│   ├── kind/profiles/           # Tier 1 cluster profiles: calico (default), nocni, cilium, ...
│   ├── vagrant/                 # Tier 2 multi-VM kubeadm environment
│   └── devcontainer/            # Tier 3 Codespaces / hosted option
├── chapters/
│   └── 07-configmaps-secrets/
│       ├── 07-configmaps-secrets.md  # the chapter text (named after the chapter)
│       ├── questions.yaml       # end-of-chapter question bank
│       ├── manifests/           # starter YAML for the reader
│       └── lab/
│           ├── lab.env          # LAB_NS, LAB_TIER, ...
│           ├── setup.sh         # idempotent: builds the starting state
│           ├── reset.sh         # returns to the starting state
│           ├── verify.sh        # per-task PASS/FAIL
│           ├── solve.sh         # automated reference solution (CI)
│           └── solutions.md     # human-readable, kept separate to avoid spoilers
├── mock-exams/                  # same layout as a chapter; make mock EXAM=<name>
│   ├── part1/                   # Part I finale, Chapters 02 to 06 (done)
│   ├── part5/ … part10/         # Part V quiz; Parts VI to X simulators (CKNE)
│   ├── kcna/  kcsa/  ckad/  cka/  cks/  ckne/
└── appendices/
```

---

## 3. Lab infrastructure

| Tier | Environment | Used for | Reset method |
| --- | --- | --- | --- |
| 0 | **netlab**: one privileged Docker container (Debian, with iproute2, tcpdump, tshark, iptables, nftables, conntrack, dnsmasq, bind9 tools, curl, openssl, and the book's `labhttp` server) in which the reader builds networks out of network namespaces | Part V: addressing, ARP, routing, NAT, DNS, TLS, netns/veth/bridge/VXLAN, iptables | `make reset` recreates the container (seconds) |
| 1 | kind (multi-node) on the reader's machine, built from a **profile** | ~70% of chapters: workloads, config, services, storage, RBAC, scheduling, and Parts VI to X | Delete namespace, or recreate the cluster; a lab on another profile rebuilds it |
| 2 | Multi-VM kubeadm cluster (**Vagrant**, decided) | Cluster install, upgrades, etcd backup/restore, node troubleshooting, most of CKS (AppArmor, seccomp, Falco, kernel-level work) | Restore VM snapshot |
| 3 | Devcontainer / Codespaces / Killercoda scenarios | Readers without capable hardware | Rebuild container / restart scenario |

**Reset contract** (identical in every chapter):

| Script | Behavior |
| --- | --- |
| `setup.sh` | Idempotent. Creates the exact starting state. Safe to run repeatedly. |
| `reset.sh` | Tears down chapter resources and re-runs `setup.sh`. |
| `verify.sh` | Runs one check per task; prints `PASS`/`FAIL` with a hint; exits non-zero on any failure. |
| `solve.sh` | Automated reference solution; CI applies it to prove `verify.sh` can pass. |
| `solutions.md` | Step-by-step solutions, one per task, in a separate file. |

Each lab runs in its own namespace (Tier 1) or snapshot (Tier 2) so that chapters never interfere with each other.

**Tier 1 cluster profiles** (`envs/kind/profiles/`, built by `tools/cluster.sh`; a lab names one with `LAB_PROFILE`, default `calico`). The marker ConfigMap `kube-system/kbook-lab-marker` records the profile, and a lab on another profile rebuilds the cluster:

| Profile | What it contains | Used by |
| --- | --- | --- |
| `calico` | Calico (NetworkPolicy), metrics-server; the default | Parts I to IV, their mocks |
| `nocni` | no CNI; nodes stay `NotReady` until the reader installs one | Ch. 48 to 50 |
| `cilium` | Cilium with kube-proxy, Hubble on | default for Parts VI and VII |
| `cilium-kpr` (planned) | Cilium kube-proxy replacement, Hubble, egress gateway, WireGuard, Gateway API, LB-IPAM | Ch. 54, 57, 59 to 60, 65 to 66, 69, 71 |
| `istio` (planned) | `cilium` + Istio (sidecar and ambient) + Gateway API + cert-manager + Prometheus/Jaeger | Ch. 61, 63, 67 to 68, 70 |
| `multi` (planned) | two clusters with non-overlapping Pod CIDRs and Cilium ClusterMesh | Ch. 62 |
| `bgp` (planned) | `cilium-kpr` + an FRR router container acting as the upstream | Ch. 59 |

Hardware: Tier 0 needs about 1 GB RAM; the `cilium` profiles about 4 GB, `istio` and `multi` about 8 GB.

**Hardware requirements to state in Chapter 3:** Tier 1 needs roughly 4 GB RAM free; Tier 2 needs roughly 5 GB more for its three VMs (with the kind cluster paused), plus about 30 GB of disk for the VMs and snapshots. Point everyone else to Tier 3.

---

## 4. Chapter template

Every chapter follows this structure:

1. **Header block:** exams served (tags), difficulty, estimated time, lab tier, prerequisites
2. **Learning objectives** (mapped to curriculum bullets)
3. **Concepts:** explanation with Mermaid diagrams
4. **Guided walkthrough:** commands with expected output
5. **Hands-on lab:** 3 to 6 tasks, each with a suggested time limit and difficulty label
6. **Exam tips:** imperative shortcuts, which docs pages to bookmark
7. **End-of-chapter questions:** 10 to 15 (multiple choice for KCNA/KCSA style; performance tasks for CKA/CKAD/CKS style)
8. **Further reading**

### Chapter definition of done

- [ ] Text reviewed against the current curriculum bullets it claims to cover
- [ ] All commands executed on the pinned Kubernetes version
- [ ] `setup.sh`, `reset.sh`, `verify.sh` implemented and idempotent
- [ ] CI run: setup, apply reference solution, `verify.sh` passes
- [ ] CI run: `verify.sh` fails on the untouched starting state (proves the checks are real)
- [ ] `reset.sh` verified after a deliberately broken lab
- [ ] Questions written, each with an explanation of the correct answer
- [ ] Coverage matrix updated
- [ ] Read by one person at the target level who was not the author

---

## 5. Chapter plan

Legend: **A** = KCNA, **S** = KCSA, **D** = CKAD, **C** = CKA, **X** = CKS, **N** = CKNE. Tier = lab environment (0, 1, 2, or none for conceptual). In Parts V to X, a CKNE domain is **D1** Core Infrastructure and CNI, **D2** Service Networking and DNS, **D3** Advanced Traffic Management, **D4** Network Security and Policy, **D5** Observability.

### Part I: Foundations

| # | Chapter | Exams | Tier |
| --- | --- | --- | --- |
| 01 | Cloud-native landscape, the CNCF, and why Kubernetes exists | A | none |
| 02 | Kubernetes architecture: control plane, nodes, API server, etcd | A C | 1 |
| 03 | Lab setup and `kubectl` fluency (contexts, output formats, `explain`, dry-run) | A D C | 1 |
| 04 | Pods in depth | A D C | 1 |
| 05 | Controllers: ReplicaSets, Deployments, rollouts and rollbacks | A D C | 1 |
| 06 | Namespaces, labels, selectors, annotations | A D C | 1 |

### Part II: Building and running applications

| # | Chapter | Exams | Tier |
| --- | --- | --- | --- |
| 07 | ConfigMaps, Secrets, environment variables, downward API | D C | 1 |
| 08 | Jobs and CronJobs | D | 1 |
| 09 | Multi-container pods: init containers, sidecars, patterns | D | 1 |
| 10 | Probes, requests/limits, QoS classes, `securityContext` and capabilities | D C | 1 |
| 11 | Services and cluster DNS | A D C | 1 |
| 12 | Ingress and Gateway API | D C | 1 |
| 13 | Storage basics: volumes, PV, PVC, StorageClass | D C | 1 |
| 14 | Helm and Kustomize | D C | 1 |
| 15 | Developer observability and maintenance: logs, metrics, debugging applications, API deprecations | A D | 1 |
| 16 | Container images and application delivery: building and changing images, CI/CD, GitOps (Argo CD, Flux), deployment strategies | A D | 1 |

### Part III: Cluster administration

| # | Chapter | Exams | Tier |
| --- | --- | --- | --- |
| 17 | Scheduling: taints, tolerations, affinity, topology spread, priority, static pods | C | 1 |
| 18 | Installing a cluster with kubeadm | C | 2 |
| 19 | Cluster upgrades and node maintenance (cordon, drain) | C | 2 |
| 20 | etcd backup and restore | C | 2 |
| 21 | Networking internals: CNI, kube-proxy, NetworkPolicy, CoreDNS | A C | 1/2 |
| 22 | Storage internals: CSI, dynamic provisioning, access modes | C | 1 |
| 23 | RBAC and ServiceAccounts | C X | 1 |
| 24 | CRDs, operators, and extension interfaces (CRI, CNI, CSI) | A C | 1 |
| 25 | Autoscaling: HPA, VPA, cluster autoscaler concepts | A C | 1 |
| 26 | Troubleshooting I: applications and networking | C | 1/2 |
| 27 | Troubleshooting II: nodes, kubelet, control plane, certificates | C | 2 |
| 28 | Cloud-native architecture: service mesh, serverless, personas, community and governance | A | none |

### Part IV: Security

| # | Chapter | Exams | Tier |
| --- | --- | --- | --- |
| 29 | Cloud-native security model: 4Cs, threat modeling, compliance frameworks | S | none |
| 30 | Cluster setup hardening: CIS benchmark (kube-bench), API server flags, TLS | S X | 2 |
| 31 | AuthN, AuthZ, and admission control (ValidatingAdmissionPolicy, OPA Gatekeeper, Kyverno) | S X | 1 |
| 32 | System hardening: AppArmor, seccomp, host OS footprint | S X | 2 |
| 33 | Microservice hardening: Pod Security Standards, securityContext, secrets management, sandboxed runtimes | S X | 2 |
| 34 | Supply chain security: image scanning, signing, SBOMs, image admission policy | S X | 1 |
| 35 | Runtime security, monitoring, and auditing: Falco, audit logs, immutability, incident response | S X | 2 |
| 36 | Network security in depth: default-deny, mTLS, encryption in transit | S X | 1 |

### Part V: Networking from zero

The CKNE assumes networking knowledge that the rest of the book does not teach. Part V builds it from zero for readers with no networking background; every chapter runs in the netlab container (Tier 0) and ends with something the reader built and can capture with `tcpdump`. Readers who know networking skim it and take its quiz.

| # | Chapter | Exams | Tier |
| --- | --- | --- | --- |
| 37 | The CKNE, and a network lab in a container: what the exam tests, the netlab (Tier 0), how cluster profiles work (drafted) | N (foundations) | 0 |
| 38 | How networks work: hosts, links, packets, layers (OSI vs TCP/IP), encapsulation, your first `tcpdump` (drafted) | N (foundations) | 0 |
| 39 | Ethernet and switching: MAC addresses, frames, ARP, broadcast domains, MTU (drafted) | N (foundations) | 0 |
| 40 | IP addressing: IPv4, binary in five minutes, CIDR and subnetting, private ranges, IPv6 basics (drafted) | N (foundations) | 0 |
| 41 | Routing and NAT: routing tables, default gateway, longest-prefix match, SNAT/DNAT/masquerade, traceroute (drafted) | N (foundations) | 0 |
| 42 | Transport: TCP vs UDP, ports, sockets, the three-way handshake, connection states, `ss` (drafted) | N (foundations) | 0 |
| 43 | DNS: names, records (A, AAAA, CNAME, SRV, PTR), resolvers, search domains, `ndots`, `dig` (drafted) | N (foundations) | 0 |
| 44 | HTTP and TLS: requests and responses, headers, HTTP/2 and gRPC, certificates, CAs, the TLS handshake, `openssl` (drafted) | N (foundations) | 0 |
| 45 | Virtual networking by hand: network namespaces, `veth` pairs, Linux bridges, overlays with VXLAN, build a two-"host" container network (drafted) | N | 0 |
| 46 | Netfilter: iptables chains and tables, nftables, conntrack, how a DNAT load balancer works (drafted) | N | 0 |
| 47 | The troubleshooting method: layer-by-layer debugging, `ip`/`ss`/`ping`/`curl`/`dig`/`tcpdump` filters, reading captures (drafted) | N | 0 |
| P5 | Part V quiz (`mock-exams/part5`, `make quiz`) (drafted) | N | none |

### Part VI: Core Infrastructure and CNI (15%)

| # | Chapter | Exams | Tier |
| --- | --- | --- | --- |
| 48 | The Kubernetes network model and CNI: the Tier 1 cluster, pod IPs, the four communication problems, what CNI is; run a plugin by hand and network a bare cluster with `ptp`, routes, and masquerading (drafted) | N | 1 `nocni` |
| 49 | Installing and configuring CNI plugins: Cilium (Helm and `cilium` CLI), Calico, Flannel, `/etc/cni/net.d`, routing vs overlay modes, MTU (drafted) | N | 1 `nocni`, 2 |
| 50 | IPAM and pod CIDR allocation: `--cluster-cidr`, node `podCIDR`, Cilium cluster-pool and multi-pool IPAM, Calico IP pools, running out of IPs (drafted) | N | 1 `nocni` |
| 51 | Multi-interface pods: Multus, `NetworkAttachmentDefinition`, macvlan/ipvlan/bridge secondary networks (drafted) | N | 1 `cilium` |
| 52 | Troubleshooting pod connectivity: pod-to-pod, cross-node, pod DNS; `kubectl debug`, ephemeral containers, `nsenter`, `tcpdump` on nodes, `cilium-dbg` | N | 1 `cilium`, 2 |
| P6 | Part VI simulator (`mock-exams/part6`) | N | 1 |

### Part VII: Service Networking and DNS (25%)

| # | Chapter | Exams | Tier |
| --- | --- | --- | --- |
| 53 | L4 Services: ClusterIP, NodePort, LoadBalancer (cloud-provider-kind / LB-IPAM), headless, ExternalName, session affinity, dual-stack (drafted) | N | 1 `cilium` |
| 54 | kube-proxy and its alternatives: iptables, IPVS, and nftables modes, reading the rules, Cilium eBPF kube-proxy replacement, migrating between them | N | 1 `calico`, `cilium-kpr` |
| 55 | Pod endpoint availability: Endpoints and EndpointSlices, readiness probes, `publishNotReadyAddresses`, `externalTrafficPolicy`/`internalTrafficPolicy`, topology-aware routing, graceful termination | N | 1 `cilium` |
| 56 | CoreDNS: architecture, the Corefile, plugins (`forward`, `rewrite`, `hosts`, `stub domains`, `cache`), custom domains, pod `dnsConfig`/`dnsPolicy`, NodeLocal DNSCache | N | 1 `cilium` |
| 57 | Gateway API: GatewayClass, Gateway, HTTPRoute, GRPCRoute, header/path matching, traffic splitting, redirects, ReferenceGrant; Cilium and Istio implementations; migrating from Ingress | N | 1 `cilium-kpr`, `istio` |
| 58 | Troubleshooting service traffic: empty endpoints, selector mismatches, port vs targetPort, DNS failures, kube-proxy rules, `hubble observe` | N | 1 `cilium-kpr` |
| P7 | Part VII simulator (`mock-exams/part7`) | N | 1 |

### Part VIII: Advanced Traffic Management (20%)

| # | Chapter | Exams | Tier |
| --- | --- | --- | --- |
| 59 | Routing to expose networks: BGP fundamentals (taught from scratch), Cilium BGP control plane peering with an FRR router, LB-IPAM pools, L2 announcements, advertising pod and service CIDRs | N | 1 `bgp` |
| 60 | Egress gateways: why fixed egress IPs matter, Cilium `CiliumEgressGatewayPolicy`, Istio egress gateway, verifying the source IP from outside | N | 1 `cilium-kpr`, `istio` |
| 61 | Service mesh traffic management: Envoy, Istio sidecar vs ambient (ztunnel, waypoints), retries, timeouts, circuit breaking, weighted routing | N | 1 `istio` |
| 62 | Cross-cluster service discovery and load balancing: Cilium ClusterMesh, global and shared services, service affinity, the Multi-Cluster Services API, Istio multicluster | N | 1 `multi` |
| 63 | Optimizing LLM traffic: why inference traffic is different (long requests, streaming, token cost, KV-cache), Gateway API Inference Extension (`InferencePool`, endpoint picker), model-aware routing, rate limiting, using simulated model servers (no GPU) | N | 1 `istio` |
| P8 | Part VIII simulator (`mock-exams/part8`) | N | 1 |

### Part IX: Network Security and Policy (25%)

| # | Chapter | Exams | Tier |
| --- | --- | --- | --- |
| 64 | Kubernetes NetworkPolicy: default deny, ingress and egress rules, pod/namespace selectors, ipBlock, allowing DNS, testing a policy matrix | N | 1 `cilium` |
| 65 | CNI policies beyond the standard: `CiliumNetworkPolicy` and `CiliumClusterwideNetworkPolicy` (L7 HTTP rules, DNS/FQDN egress, entities), Calico `GlobalNetworkPolicy`, AdminNetworkPolicy | N | 1 `cilium-kpr`, `calico` |
| 66 | Node and pod level encryption: Cilium WireGuard and IPsec (pod-to-pod, node-to-node), Istio mTLS, proving encryption with `tcpdump` | N | 1 `cilium-kpr`, `istio` |
| 67 | TLS certificates for Gateway API: cert-manager (Issuers, Certificates), TLS termination and passthrough on a Gateway, `BackendTLSPolicy`, rotation and expiry debugging | N | 1 `istio` |
| 68 | Pod-level authentication and authorization: workload identity and SPIFFE, Istio `PeerAuthentication`, `RequestAuthentication` (JWT), `AuthorizationPolicy`; Cilium mutual authentication | N | 1 `istio` |
| P9 | Part IX simulator (`mock-exams/part9`) | N | 1 |

### Part X: Observability (15%)

| # | Chapter | Exams | Tier |
| --- | --- | --- | --- |
| 69 | Analyzing network health with metrics: golden signals, Prometheus and PromQL basics, Hubble metrics, Istio/Envoy metrics, drops and retransmits, Grafana dashboards | N | 1 `cilium-kpr`, `istio` |
| 70 | End-to-end tracing: spans and context propagation, OpenTelemetry, Jaeger with Istio, finding the slow hop | N | 1 `istio` |
| 71 | Auditing traffic with logs: Hubble flow logs and policy verdicts, Envoy access logs, CoreDNS query logs, exporting flows | N | 1 `cilium-kpr`, `istio` |
| P10 | Part X simulator (`mock-exams/part10`) | N | 1 |

### Part XI: Exam readiness

| # | Chapter | Exams | Tier |
| --- | --- | --- | --- |
| 72 | Terminal speed: aliases, `vim`, `tmux`, `jq`/`yq`, imperative commands | D C X | 1 |
| 73 | Navigating the allowed documentation (with the Cilium and Istio docs for the CKNE) | D C X N | none |
| 74 | Exam logistics and study plans per certification (six exams) | all | none |
| P1 | Part I simulator: the killer.sh-style finale of Part I, over Chapters 02 to 06 (done, `mock-exams/part1`) | D C | 1 |
| M1-M5 | Mock exams: KCNA, KCSA (question banks); CKAD, CKA, CKS (timed performance-based, killer.sh style) | all | 1/2 |
| M6 | CKNE simulators `mock-exams/ckne` and `ckne2` (planned): 120 min, about 17 weighted questions, domain-weighted, multiple contexts | N | 1/2 |

### Appendices

Command cheat sheet · YAML snippets · JSONPath reference · networking glossary (`appendices/glossary.md`, done for Part V) · networking and tool cheat sheets (`ip`, `ss`, `dig`, `tcpdump`, `cilium`, `hubble`, `istioctl`) · solution index · troubleshooting the lab environments

---

## 6. Coverage matrix

Maintain `docs/coverage-matrix.md` as a table with one row per curriculum bullet:

| Exam | Domain | Bullet (verbatim from curriculum) | Chapter | Lab task | Question IDs | Status |
| --- | --- | --- | --- | --- | --- | --- |

This is the proof of "covers all materials." Review it at the end of every phase and before every release.

---

## 7. Phases and milestones

Estimates assume one author working part-time; adjust for your pace and any co-authors.

### Phase 0: Foundations (2 to 3 weeks)

*Status (2026-10-15): done except the outside reader. The framework, CI, and the pilot run against a real kind cluster; the hardening pass (exact-context plus cluster-marker safety check, no implicit kubeconfig changes, read-only `verify`, sentinel survival, schema validation, version-drift check, framework test harness) is in place.*

- [x] Style guide, chapter template, lab-authoring guide
- [x] Repo skeleton, `versions.env`, Makefile targets (`lab`, `reset`, `verify`, `solve`)
- [x] Shared shell library (`tools/lib.sh`) with assertion and wait helpers
- [x] CI pipeline: markdown lint, shellcheck, yamllint, kind-based lab runner
- [x] Question-bank format and renderer
- [x] Coverage matrix populated from all five current curricula
- [ ] **Pilot chapter (Ch. 04) finished to the full definition of done** (only the outside reader is missing)
- **Exit criterion:** a stranger can clone the repo, run `make lab CH=04`, complete the lab, break it, and `make reset CH=04`.

### Phase 1: Parts I and II (~8 weeks)

*Status (2026-10-15): Chapters 01 to 16 and the Part I and Part II mock exams are drafted, and every Tier 1 lab passes `make test` on kind. Not yet read by anyone at the target level.*

- [x] Chapters 01 to 16 drafted and tested
- [ ] Chapters 01 to 16 reviewed by a reader at the target level
- [ ] Tier 3 devcontainer working (`envs/devcontainer` does not exist yet). Backlog since 2026-11-14
- **Exit criterion:** all Tier 1 labs pass the CI loop; coverage matrix shows KCNA and CKAD material complete.

### Phase 2: Part III (~8 weeks)

*Status (2026-10-15): 17 to 28 are drafted and tested (18 to 20 and 27 by hand on the VMs). The Part III mock exam (on the VMs) is done; Part III is complete apart from outside review.*

- [x] Tier 2 environment built first: Vagrant config, staged build, snapshot-based reset (`envs/vagrant`, verified by hand 2026-10-12 with `make test-tier2-env` on all three snapshots)
- [x] Chapters 17 to 28
- [x] Part III mock exam (`mock-exams/part3`, on the Tier 2 VMs; verified by hand 2026-10-15)
- **Exit criterion:** a full kubeadm cluster can be rebuilt from scratch, upgraded, and restored from an etcd backup by following the book alone.

### Phase 3: Part IV (~8 weeks)

*Status (2026-11-13): 30 to 36 are drafted and tested (30, 32, 33, and 35 on the Tier 2 VMs); 29 is drafted (concept chapter, no lab). Part IV is complete apart from outside review.

- [ ] Chapters 29 to 36; pin and test Trivy, Falco, kube-bench, Kyverno/Gatekeeper versions
- **Exit criterion:** every CKS and KCSA bullet in the coverage matrix is mapped and tested.

### Phase 4: Part V and mock exams (~4 weeks)

*Status (2026-10-23): 37 is drafted and tested; 38 and 39 are drafted (concept chapters, no lab). The KCNA practice exam (`mock-exams/kcna`, 60 questions, `make quiz`) is done, and so are the full CKAD simulator (`mock-exams/ckad`, 20 questions over every CKAD domain) and the full CKA simulator (`mock-exams/cka`, 18 questions over every CKA domain, on the Tier 2 VMs). Second sets followed on 2026-10-30: `kcna2` (60 more questions), `ckad2` (20), and `cka2` (18, on the VMs), each with no question repeated from the first set. The full CKS simulator (`mock-exams/cks`, 15 questions over every CKS domain, on the Tier 2 VMs) followed on 2026-11-13. The KCSA practice exam (`mock-exams/kcsa`, 60 questions over the six KCSA domains, `make quiz`) followed on 2026-11-14, so every exam now has a practice set.*

- [x] Chapters 72 to 74
- [ ] Five mock exams; time-test each yourself and record how long it took
- **Exit criterion:** mock exams reflect exam format and difficulty, and a beta reader finishes a mock within the allotted time on a first attempt only after studying the book.

### Phase 4b: the CKNE Parts V to X (~6 months)

*Status (2026-11-20): merged from the separate CKNE course. Part V (Chapters 37 to 47), its quiz (`mock-exams/part5`, 40 questions), and the glossary are drafted and pass `make test-tier0`; Chapters 48 to 50 (`nocni`), 51 and 53 (`cilium`) are drafted. Not yet read by anyone at the target level.*

- [x] Tier 0 netlab and the `calico`, `nocni`, and `cilium` profiles (`tools/cluster.sh`)
- [x] Part V and its quiz; the glossary for every Part V term
- [x] Chapter 49 (2026-11-20), Chapter 50 and 51 (2026-11-21)
- [ ] Chapter 52 and 54 to 58; Part VI and VII simulators (`part6`, `part7`)
- [ ] `cilium-kpr`, `bgp`, `istio`, and `multi` profiles stable in CI; Chapters 59 to 68; `part8`, `part9`
- [ ] Chapters 69 to 71; `part10`; full simulators `ckne` and `ckne2`
- [ ] Part V read by a beginner with no networking background
- **Exit criterion:** every CKNE competency in the coverage matrix is mapped and tested in CI, the heavy profiles run in 8 GB, and a beta reader finishes a full CKNE simulator within 120 minutes above the pass mark after studying the book.

### Phase 5: Beta and release (4+ weeks)

- [ ] Recruit 3 to 5 beta readers at the target level
- [ ] Collect stuck-points per chapter; fix environment bugs first, prose second
- [ ] Full re-verification against current curricula and Kubernetes version
- [ ] Release v1.0; publish errata process

**Total:** roughly 8 to 10 months part-time. Labs and environments take more effort than the prose.

---

## 8. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Curriculum or Kubernetes version changes mid-project | Single `versions.env`; coverage matrix; CI re-runs all labs on a version bump |
| Lab scripts rot over time | Every lab in CI; scheduled weekly CI run against pinned and latest versions |
| Verifier scale: ~100 hand-written `verify.sh` files become a maintenance burden | Revisit around 15 labs: if the same check patterns keep repeating, add a declarative `checks:` schema (resource, field, equals) for the simple cases and keep custom shell for behavioural ones. Not worth building at 3 labs |
| Tier 2 hardware requirements exclude readers | Tier 3 hosted option; document minimum specs clearly |
| Labs work on the author's machine only | Beta readers on Linux, macOS, and Windows (WSL2); CI on Linux |
| Security tooling (Falco, Trivy) changes quickly | Pin versions; isolate tool setup in per-chapter `setup.sh` |
| Scope creep (topics beyond the exams) | Every section must map to a coverage-matrix row, or go in "Further reading" |
| The CKNE is brand new; its curriculum, weights, or allowed docs may change, and third-party facts may be wrong | Coverage matrix; re-check the curriculum at every phase boundary; logistics marked unconfirmed until checked against official pages |
| Heavy profiles (Istio, two clusters) exceed reader laptops | Profiles load only what a chapter needs; document RAM per profile; `make cluster-pause` and the netlab for Part V |
| Cilium, Istio, Gateway API, and the Inference Extension change fast | Pin everything in `versions.env`; weekly CI; per-profile install scripts |
| LLM traffic usually needs GPUs | Use simulated model servers behind the real Inference Extension; teach the routing, not the model |
| Networking checks are flaky (timing, conntrack caching) | Probe pods with explicit timeouts, `wait_for` retries, and clearing conntrack in `reset.sh` where a lab needs it |
| Copying exam content | Write original questions and scenarios from the public curricula only; never reproduce real exam questions |

---

## 9. Immediate next steps

1. ~~Decide the Kubernetes version~~ Decided 2026-10-15 to stay on v1.35; on 2026-10-23 the Linux Foundation moved the CKA and the CKAD to v1.37, and the book moved its pin to v1.37.0 (previous version v1.36.5), re-running every lab and re-capturing the output that depends on the version. Check again before the beta.
2. ~~Finish Part III on the VMs~~ Done 2026-10-15: Chapters 18, 19, 20, and 27.
3. ~~Write the Part III mock exam~~ Done 2026-10-15 (`mock-exams/part3`).
4. ~~Finish Part IV~~ Done 2026-11-13 (29, 30, and 33 drafted 2026-10-24; 32 on 2026-11-09; 35 on 2026-11-13). Close the "Minimize base image footprint" gap in 34 (or 16).
5. Backlog (2026-11-14): build the Tier 3 devcontainer, so readers without the hardware for Tier 2 have a path. Deferred until outside readers ask for it.
6. Find the first outside reader, starting with the pilot chapter (04).
7. CKNE (merged 2026-11-20): Chapters 49 and 50 drafted 2026-11-20/21; Chapter 51 drafted 2026-11-21; next Chapter 52, then 54 to 58 (the `cilium-kpr` profile first); find a beginner reader for Part V.
