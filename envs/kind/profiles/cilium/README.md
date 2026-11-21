# Profile `cilium`

The default profile of Parts VI and VII: Cilium (`CILIUM_VERSION`) in its default VXLAN
overlay mode, with Kubernetes host-scope IPAM (each node's `podCIDR` from
10.244.0.0/16), kube-proxy still running in iptables mode, and Hubble with
Hubble Relay enabled. Used by most chapters of Parts VI and VII from Chapter 51 on.
