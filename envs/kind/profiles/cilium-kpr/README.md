# Profile `cilium-kpr`

Cilium (`CILIUM_VERSION`) with **kube-proxy replacement**: the cluster has no
kube-proxy at all (kind's `kubeProxyMode: none`), and Cilium's eBPF programs
handle every Service. Otherwise like `cilium` (VXLAN overlay, Kubernetes
host-scope IPAM from 10.244.0.0/16, Hubble with Hubble Relay), plus what the
later chapters build on:

| Feature | Setting | Chapters |
| --- | --- | --- |
| kube-proxy replacement | `kubeProxyReplacement=true`, Cilium talks to the API server on the control plane node | 54, 58 |
| LoadBalancer IPs | LB-IPAM pools (created by the labs) and L2 announcements on the kind network | 54, 59 |
| Egress gateway | `egressGateway.enabled`, with `bpf.masquerade` | 60 |
| Gateway API | the CRDs at `GATEWAY_API_VERSION` (standard channel, plus TLSRoute), `gatewayAPI.enabled` | 57 |
| WireGuard | off; Chapter 66 turns it on | 66 |
| Hubble | Hubble and Hubble Relay | 58, 69, 71 |

About 4 GB of RAM, like `cilium`.
