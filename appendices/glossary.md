# Appendix: Networking glossary

Every networking term Parts V to X define, in alphabetical order, with the
chapter that introduces it. Part VI onward adds Kubernetes networking terms as it goes.

## Numbers and symbols

- **4-tuple / 5-tuple**: source address, source port, destination address, destination port (plus the protocol, for the 5-tuple). Identifies one connection. (42)
- **`0.0.0.0`**: as a listening address, "every address this host has"; as a route (`0.0.0.0/0`), the default route. (40, 42)
- **`::`**: in an IPv6 address, shorthand for one run of all-zero groups; may appear once. (40)

## A

- **ACK**: TCP flag that acknowledges received data. Shown as `.` in tcpdump. (42)
- **Agent** (CNI): the plugin's long-running Pod on every node, usually from a DaemonSet; it installs the binary and configuration and maintains the node's routes and rules. (49)
- **ALPN** (Application-Layer Protocol Negotiation): TLS extension in which client and server agree on HTTP/2 or HTTP/1.1. (44)
- **Application layer**: the top layer of the TCP/IP model; what programs say to each other (HTTP, DNS, TLS). (38)
- **ARP** (Address Resolution Protocol): finds the MAC address that belongs to an IP address on the local network, by broadcast. (39)
- **ARP cache / neighbour table**: a host's stored IP-to-MAC mappings, shown by `ip neigh`. (39)
- **Authoritative server**: a DNS server that holds a zone's records and gives the official answers for it. (43)

## B

- **Base chain** (nftables): a chain attached to a netfilter hook. (46)
- **Block** (IPAM): a fixed-size piece of a pool that one node owns, such as a Calico `/26` or a Cilium multi-pool `/28`; nodes claim more blocks as they need them. (50)
- **Bridge** (Linux): a software switch in the kernel; interfaces attached to it become its ports. (39)
- **Broadcast address**: an address that reaches every host on a network: `ff:ff:ff:ff:ff:ff` in Ethernet, all host bits 1 in an IPv4 subnet. (39, 40)
- **Broadcast domain**: all hosts that receive each other's broadcasts; one LAN, one layer 2 network. (39)

## C

- **CA** (certificate authority): signs certificates; clients trust a certificate if they trust the CA that signed it. (44)
- **Capture file** (pcap): raw packets saved by `tcpdump -w`, read with `tcpdump -r` or Wireshark. (38)
- **Certificate**: a signed document that binds a public key to names (SANs) for a period of time. (44)
- **Chain** (iptables): an ordered list of rules, either built in (one per hook) or custom. (46)
- **Chain of trust**: the sequence of certificates from a server's certificate up to a CA the client trusts. (44)
- **CIDR notation**: an address or subnet with its prefix length, such as `10.0.4.0/24`. (40)
- **`cilium-dbg`**: the command-line tool inside each Cilium agent Pod; asks that node's agent about its status, endpoints, and drops. (52)
- **CiliumLoadBalancerIPPool**: the Cilium object that lists the address blocks LB-IPAM hands out to LoadBalancer Services. (53)
- **CiliumNode**: Cilium's per-node object, holding the address blocks the operator allocated to the node. (50)
- **CiliumPodIPPool**: a multi-pool IPAM pool (`cilium.io/v2alpha1`): a list of CIDRs and a block size. (50)
- **ClientHello**: the first TLS handshake message; carries SNI and ALPN in the clear. (44)
- **Cluster CIDR**: the address range for all Pods of a cluster (`--cluster-cidr`, kind's `podSubnet`), from which each node's `podCIDR` is carved. (48)
- **Cluster-pool IPAM**: Cilium's default IPAM mode; its operator hands each node a range from Cilium's own pool (`10.0.0.0/8` by default), ignoring the node's `podCIDR`. (49)
- **ClusterIP**: a Service's virtual IP from the service CIDR, reachable only inside the cluster; also the default Service type. (53)
- **CNAME**: DNS record that makes one name an alias for another. (43)
- **CNI** (Container Network Interface): the specification, and the plugins, that connect a Pod's network namespace to the network. (45)
- **CNI plugin**: an executable in `/opt/cni/bin` that the container runtime runs once per Pod to wire (`ADD`) or unwire (`DEL`) its network namespace; input in environment variables and JSON on stdin, result as JSON on stdout. (48)
- **CNI result**: the JSON a CNI plugin prints after `ADD`: the interfaces it created, the addresses, and the routes. (48)
- **Configuration list** (`.conflist`): a CNI configuration file with a network name and a chain of plugins that run in order on `ADD` and in reverse on `DEL`. (48)
- **Connected route**: the route a host creates automatically for the subnet of each of its addresses. (40, 41)
- **Connection refused**: the target answered a connection attempt with a reset: nothing listens there, or a REJECT rule. (42)
- **Connection timed out**: no answer came back: packets lost or dropped on the way. (42)
- **conntrack** (connection tracking): netfilter's table of connections; remembers NAT translations and gives packets a state. (41, 46)
- **Container**: a process running in its own set of namespaces, with resource limits; shares the host's kernel. (45)
- **crictl**: the container runtime's command-line client on a node: lists containers and shows their details, such as their PID. (52)
- **CSR** (certificate signing request): a public key plus requested names, sent to a CA to be signed. (44)

## D

- **Datagram**: a single UDP message. (38, 42)
- **Decapsulation**: removing the headers of each layer on receipt. (38)
- **Default gateway / default route**: the route used when nothing more specific matches (`default` = `0.0.0.0/0`) and the router it points to. (41)
- **Delegate** (CNI): a plugin that a meta-plugin such as Multus calls on a Pod's behalf. (51)
- **DNAT** (destination NAT): rewriting the destination address (and port) of packets; port forwarding, Service virtual IPs. (41, 46)
- **DNS** (Domain Name System): translates names into addresses (and more). (43)
- **`dnsPolicy`**: the Pod field that decides what the kubelet writes into the Pod's `/etc/resolv.conf`; `ClusterFirst` by default, while `Default` means the node's resolver. (52)
- **Domain**: a part of the DNS name tree, such as `lab.internal`. (43)
- **Dotted-decimal**: writing an IPv4 address as four decimal octets separated by dots. (40)
- **DROP / REJECT**: firewall targets: discard silently (client times out) / answer with an error (client fails at once). (42, 46)
- **Dual-stack**: both IPv4 and IPv6 addresses on every Pod and Service. (40)

## E

- **eBPF**: small programs loaded into the Linux kernel and attached to interfaces or other hooks; Cilium's data plane. (49)
- **Egress gateway**: a chosen exit point where outgoing traffic is SNATed to a known address. (05; Chapter 60)
- **Encapsulation**: each layer wrapping the data of the layer above in its own header. (38)
- **Encapsulation overhead**: the bytes an overlay adds to every packet; 50 for VXLAN over IPv4, 20 for IP-in-IP. (49)
- **Endpoint** (Cilium): a Pod (or other workload) that a Cilium agent manages on its node, with an ID and a security identity. (52)
- **Endpoints / EndpointSlice**: the objects that list the ready Pod addresses and ports behind a Service; EndpointSlices are the current form. (53)
- **Ephemeral container**: an extra container that `kubectl debug` adds to a running Pod, in its namespaces, for debugging; it stays until the Pod is deleted. (52)
- **Ephemeral port**: a random port the kernel picks for the client end of a connection. (42)
- **Established**: a TCP connection whose handshake has completed (`ESTAB` in `ss`); also a conntrack state. (42, 46)
- **Ethernet**: the link-layer protocol of almost every wired network and every Kubernetes node. (39)
- **ExternalName Service**: a Service with no address that CoreDNS answers with a CNAME to another name. (53)

## F

- **FDB** (forwarding database): a switch's or bridge's MAC address table, shown by `bridge fdb show`. (39)
- **FIN**: TCP flag that says "I am done sending". (42)
- **Flood**: a switch sending a frame out of every port, for broadcasts and unknown destinations. (39)
- **Forwarding**: a host passing on packets not addressed to itself; on Linux, `net.ipv4.ip_forward=1`. (41)
- **Frame**: the unit of data at the link layer; carries a packet. (38, 39)

## G

- **Gateway / next hop**: the router a route points to. (41)
- **Geneve**: an overlay protocol similar to VXLAN, on UDP port 6081. (45)
- **gRPC**: a remote-procedure-call protocol that runs on HTTP/2. (44)

## H

- **Handshake** (TCP): SYN, SYN-ACK, ACK; sets up a connection. (42)
- **Header**: the information in front of a packet's payload: addresses and handling instructions. (38)
- **Headless Service**: a Service with `clusterIP: None`; its DNS name returns the Pods' addresses instead of a virtual IP. (53)
- **Hook** (netfilter): a fixed point on a packet's path where rules run: PREROUTING, INPUT, FORWARD, OUTPUT, POSTROUTING. (46)
- **Hop**: one router on a path. (41)
- **Host**: a device that sends and receives data, with an IP address. (38)
- **Host part**: the bits of an IP address after the prefix; identifies the host within its subnet. (40)
- **`host-local`**: the reference IPAM plugin; hands out addresses from configured ranges and records them in files under `/var/lib/cni/networks/` on the node. (48)
- **`hostNetwork`**: a Pod setting that skips the Pod's own network namespace; the Pod uses the node's interfaces and address and needs no CNI plugin. (48)
- **HTTP**: the request-response protocol of the web and of most APIs. (44)
- **HTTPS**: HTTP inside TLS, port 443 by default. (44)

## I

- **ICMP** (Internet Control Message Protocol): helper protocol for tests (ping) and error messages (unreachable, time exceeded). (38, 41)
- **`iflink`**: in `/sys/class/net/<if>/iflink`, the index of the other end of a veth pair; shown as `@ifN` by `ip link`. (52)
- **Interface** (network interface): a host's connection point to a network, such as `eth0`. (37)
- **Internet layer**: the TCP/IP layer that gets packets between hosts across networks (IP). (38)
- **IP address**: the address that identifies a host on an IP network. (37, 40)
- **IP pool** (Calico): an `IPPool` resource, a range Calico cuts into per-node blocks; `192.168.0.0/16` by default. (50)
- **IP-in-IP**: an overlay that wraps an IP packet directly in a second IP header; Calico's classic tunnel. (49)
- **IPAM** (IP Address Management): handing out addresses from a range; in Kubernetes, giving each node a Pod subnet and each Pod an address. (40, 45)
- **IPAM plugin**: a CNI plugin that only chooses addresses (for example `host-local`), called by the main plugin through its `ipam` section. (48)
- **iptables**: the classic tool for netfilter rules; today usually iptables-nft, which stores them as nftables tables. (41, 46)
- **IPv4 / IPv6**: 32-bit / 128-bit Internet Protocol addresses. (40)
- **ipvlan**: a CNI plugin and Linux interface type: a virtual interface on top of a node interface, sharing its MAC address. (51)

## K

- **Kernel**: the core of the operating system; owns the network interfaces and does encapsulation, routing, and filtering. (38)
- **kind** (Kubernetes in Docker): a tool that runs each Kubernetes node as a Docker container; the book's Tier 1 lab cluster. (48)
- **kube-proxy**: the node agent that turns Services and EndpointSlices into forwarding rules (iptables, IPVS, or nftables) on every node. (53)
- **`kubectl debug node/<node>`**: starts a Pod in a node's network namespace with an image of your choice (for example netshoot), for node-level troubleshooting. (48)
- **Kubernetes host-scope IPAM**: Cilium's `ipam.mode=kubernetes`; Pod addresses come from each node's `podCIDR`. (49)
- **Kubernetes network model**: every Pod has its own IP; every Pod reaches every other Pod by that IP without NAT; node agents reach the Pods on their node. (48)

## L

- **L2, L3, L4, L7**: OSI layer numbers in everyday use: link, network (IP), transport (ports), application (HTTP). (38)
- **Label** (DNS): one dot-separated part of a name. (43)
- **Layer**: one level of the protocol stack, solving one problem and relying on the layer below. (38)
- **LB-IPAM**: Cilium's feature that assigns external addresses to LoadBalancer Services from CiliumLoadBalancerIPPools. (53)
- **Link**: a connection between two devices: a cable, radio, or veth pair. (38)
- **Link layer**: the TCP/IP layer that carries frames across one link (Ethernet). (38)
- **Link-local address**: valid only on one link: `169.254.0.0/16` in IPv4, `fe80::/10` in IPv6. (40)
- **Listen**: a server socket waiting for connections (`LISTEN` in `ss`). (42)
- **LoadBalancer Service**: a NodePort Service plus an external address provided by a cloud or an implementation such as Cilium LB-IPAM or MetalLB. (53)
- **Longest prefix match**: when several routes match, the most specific one wins. (41)
- **Loopback**: a host's interface to itself (`lo`, `127.0.0.1`, `::1`). (37, 40)

## M

- **MAC address**: a 48-bit link-layer address, written as six hex bytes. (39)
- **macvlan**: a CNI plugin and Linux interface type: a virtual interface on top of a node interface, with its own MAC address on that network. (51)
- **Masquerade**: SNAT to whatever address the outgoing interface has. (41)
- **Meta-plugin**: a CNI plugin that does no networking itself and calls other plugins instead. (51)
- **Method** (HTTP): what a request asks for: GET, POST, PUT, DELETE, ... (44)
- **MSS** (maximum segment size): the largest payload one TCP segment carries, announced in the handshake; the MTU minus 40 bytes for IPv4. (49)
- **MTU** (maximum transmission unit): the largest packet an interface sends or accepts in one frame; 1500 on standard Ethernet. (39)
- **mTLS** (mutual TLS): TLS in which the client also presents a certificate. (44)
- **Multi-pool IPAM**: Cilium's `ipam.mode=multi-pool`; several pools, chosen per namespace or Pod with the annotation `ipam.cilium.io/ip-pool`, handed out to nodes in blocks on demand. (50)
- **Multus**: a CNI meta-plugin that gives Pods secondary interfaces: it calls the cluster network, then one delegate per requested network. (51)

## N

- **Named port**: a container port with a name, which a Service's `targetPort` can refer to instead of a number. (53)
- **Namespace** (Linux): a kernel feature that gives processes a private view of one resource; the network namespace isolates interfaces, addresses, routes, and rules. (37, 45)
- **NAT** (network address translation): rewriting addresses in packets as they pass a router. (41)
- **Native routing**: Pod packets travel between nodes unchanged, using routes to each node's Pod subnet. (45)
- **Neighbor Discovery**: IPv6's replacement for ARP. (40)
- **Netfilter**: the packet-filtering framework in the Linux kernel. (41, 46)
- **Network**: devices that can send data to each other. (38)
- **Network address**: the first address of a subnet (all host bits 0); names the subnet. (40)
- **Network part**: the prefix bits of an IP address; identifies the network. (40)
- **Network selection annotation**: `k8s.v1.cni.cncf.io/networks` on a Pod; names the NetworkAttachmentDefinitions to attach, optionally with addresses and interface names. (51)
- **Network status annotation**: `k8s.v1.cni.cncf.io/network-status`, written by Multus; lists every interface a Pod got. (51)
- **NetworkAttachmentDefinition** (NAD): a namespaced object whose `spec.config` is a CNI configuration for a secondary network. (51)
- **`NetworkReady=false`**: the node condition message the runtime reports while it has no working CNI configuration; the node stays `NotReady`. (48)
- **nftables**: the successor of iptables, with the `nft` command. (46)
- **Node CIDR mask size**: the prefix length of the range the controller manager gives each node from the cluster CIDR (`--node-cidr-mask-size`, `/24` by default for IPv4). (50)
- **NodePort Service**: a Service that also opens the same port (30000 to 32767) on every node's address. (53)
- **nsenter**: runs a command inside the namespaces of another process, for example a container's network namespace (`-n`). (52)
- **NXDOMAIN**: DNS status meaning the name does not exist. (43)

## O

- **Octet**: eight bits; one of the four numbers of an IPv4 address. (40)
- **On-link**: directly reachable on an interface, without a router. (40, 41)
- **Operator** (Cilium): the cluster-wide controller next to the agents; it handles work not tied to one node, such as IPAM ranges and cleanup. (49)
- **OSI model**: an older seven-layer model whose numbering (L2, L3, L4, L7) is still used. (38)
- **Overlay network**: a network carried inside another by encapsulation, such as Pod traffic in VXLAN between nodes. (38, 45)

## P

- **Packet**: a unit of data with a header; strictly, the internet-layer unit (IP). (38, 39)
- **Path MTU discovery**: senders learning the smallest MTU on a path from ICMP "fragmentation needed" messages. (45)
- **Payload**: the data a packet carries, after its header. (38)
- **Pod**: Kubernetes' unit of scheduling; one network namespace shared by its containers. (45)
- **Pod CIDR**: the address range a cluster's Pods are given, split into one subnet per node. (40)
- **`podCIDR`** (node `spec.podCIDR`): the block of Pod addresses (a /24 by default) the controller manager assigns to one node. (48)
- **Policy** (iptables): what a built-in chain does with packets no rule decided on. (46)
- **Port**: a 16-bit number in the transport header that selects a socket, and so a program, on a host. (38, 42)
- **Port forwarding**: DNAT that publishes an internal service on a router's address and port. (41)
- **`portmap`**: a chained CNI plugin that implements a Pod's `hostPort` with DNAT rules. (48)
- **Prefix length**: the number of leading bits that form the network part (`/24`). (40)
- **Private address**: from the ranges `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`; not routed on the internet. (40)
- **Private key / public key**: a key pair; what one encrypts or signs, the other decrypts or verifies. (44)
- **Protocol**: an agreement on message formats and rules between communicating parties. (38)
- **`ptp`**: a reference CNI plugin that gives each Pod a veth pair and a host route on the node, with no bridge. (48)
- **PTR**: DNS record that maps an address to a name (reverse lookup). (43)

## R

- **Recursive resolver**: a DNS server that finds answers for clients by asking other servers, and caches them. (43)
- **Resource record**: one DNS entry: name, type, TTL, data. (43)
- **Retransmission**: TCP sending an unanswered segment again, such as a SYN with the same sequence number after one second. (52)
- **Reverse lookup**: finding the name of an address, through a PTR record. (43)
- **Root** (DNS): the top of the name tree, the final dot of a fully qualified name. (43)
- **Router**: a device that forwards packets between networks by IP address. (39, 41)
- **Routing table**: a host's list of routes, shown by `ip route`. (41)
- **RST**: TCP flag that refuses or aborts a connection. (42)
- **Rule** (iptables): matches plus a target. (46)

## S

- **SAN** (Subject Alternative Name): the host names (and addresses) a certificate is valid for. (44)
- **Sandbox** (Pod sandbox): the environment, including the network namespace, that the runtime creates for a Pod before starting its containers. (48)
- **Search list**: domains the resolver appends to names that are not fully qualified (`search` in `resolv.conf`). (43)
- **Secondary interface / secondary network**: a Pod interface besides `eth0`, on a network outside the cluster network; Kubernetes features do not apply to it. (51)
- **Segment**: the unit of data at the TCP layer. (38)
- **Sequence numbers**: TCP's numbering of every byte, used for ordering and retransmission. (42)
- **SERVFAIL**: DNS status meaning the server could not get an answer. (43)
- **Service**: a Kubernetes object that gives a set of Pods, chosen by label selector, one stable virtual address and DNS name, and spreads connections across them. (53)
- **Service CIDR**: the address range ClusterIPs come from (`10.96.0.0/16` in the lab cluster). (53)
- **Session affinity** (`sessionAffinity: ClientIP`): sending every connection from one client address to the same endpoint. (53)
- **SNAT** (source NAT): rewriting the source address of packets. (41)
- **SNI** (Server Name Indication): the host name a TLS client sends unencrypted in its ClientHello. (44)
- **Socket**: the kernel's handle for one end of network communication, identified by address and port. (42)
- **SRV**: DNS record that names the host and port of a service. (43)
- **Static IPAM**: the `static` IPAM plugin; with the `ips` capability, each Pod names its own address. (51)
- **Status code** (HTTP): the three-digit result of a request: 2xx success, 3xx redirect, 4xx client error, 5xx server error. (44)
- **Stub resolver**: the resolver library inside programs; sends questions to a recursive resolver. (43)
- **Subnet**: a range of addresses that share a network part, written as `10.0.4.0/24`. (40)
- **Subnet mask**: the prefix length written as a dotted-decimal mask (`255.255.255.0` = /24). (40)
- **Subnetting**: splitting a network into smaller subnets. (40)
- **Switch**: a device that forwards frames between hosts on one network by MAC address. (39)
- **SYN / SYN-ACK**: the first two packets of the TCP handshake. (42)

## T

- **Table** (iptables): a group of chains by purpose: filter, nat, mangle, raw. (46)
- **Target** (iptables): what a matching rule does: ACCEPT, DROP, REJECT, DNAT, jump to a chain, ... (46)
- **`targetPort`**: the port on the Pods that a Service forwards to; defaults to the Service's `port`. (53)
- **TCP** (Transmission Control Protocol): reliable, ordered byte streams over connections. (42)
- **TCP/IP model**: the internet's four layers: link, internet, transport, application. (38)
- **Thick plugin** (Multus): Multus as a node daemon plus the small `multus-shim` binary the runtime calls. (51)
- **TLS** (Transport Layer Security): encryption, integrity, and authentication on top of TCP. (44)
- **Top-level domain** (TLD): a label directly under the DNS root, such as `com` or `internal`. (43)
- **Transport layer**: the TCP/IP layer that picks the program on a host by port (TCP, UDP). (38)
- **TTL** (time to live): in IP, a hop counter that each router lowers by one; in DNS, how long an answer may be cached. (41, 43)
- **Tunnel mode**: a CNI routing mode in which Pod packets between nodes are wrapped in an overlay (VXLAN or Geneve), so the underlay sees only node addresses. (49)

## U

- **UDP** (User Datagram Protocol): connectionless datagrams, no delivery guarantees. (42)
- **Underlay**: the real network that carries an overlay. (45)
- **Unicast**: addressed to one specific host. (39)
- **Unique local address**: IPv6's private range, `fd00::/8`. (40)

## V

- **veth pair**: two virtual interfaces joined back to back; a virtual cable, often between namespaces. (45)
- **Virtual host**: one of several sites served at one address, selected by the Host header or SNI. (44)
- **Virtual IP** (VIP): an address no interface has, which rules (DNAT) send to real backends; a Kubernetes Service's ClusterIP. (46)
- **VNI** (VXLAN Network Identifier): the number that identifies one VXLAN overlay. (45)
- **VXLAN**: an overlay protocol that wraps Ethernet frames in UDP (port 4789). (45)

## W

- **Well-known port**: a port below 1024 with an agreed use, such as 22 (SSH), 53 (DNS), 80 (HTTP), 443 (HTTPS). (42)
- **Whereabouts**: a cluster-wide IPAM plugin that keeps its leases in the Kubernetes API. (51)

## Z

- **Zone** (DNS): the part of the name tree one owner is responsible for, served by its authoritative servers. (43)
