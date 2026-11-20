# Mock exam: Part V quiz

> **Covers:** Part V, Chapters 38 to 47: packets and Ethernet (8 questions), addressing, routing, and NAT (10), TCP and UDP (6), DNS, HTTP, and TLS (8), namespaces, overlays, netfilter, and troubleshooting (8)
> **Format:** 40 multiple-choice questions, 60 minutes, pass mark 75%
> **Lab tier:** none (no lab needed)
> **Prerequisites:** Chapters 37 to 47

The CKNE has no multiple-choice questions, but this quiz is a quick check that
the foundations stuck before Part VI builds on them. Take it in the terminal,
timed:

```bash
make quiz EXAM=part5          # start, or resume, an attempt
make quiz-reset EXAM=part5    # throw the attempt away and start over
```

Each attempt shows the questions in a new order. Answer with a letter; you can
go back and forth, flag questions, and review what is answered and flagged.
Your answers are saved after every step, so you can close the terminal and
resume, but the clock keeps running. When you submit, or when the 60 minutes
are up, you get your score per area and the explanation of every question you
missed. Below 75% in an area, reread its chapters and redo their labs before
moving on.

The questions are original and not repeated from the chapters. They are also
listed below, grouped by area, with the answers hidden at the end. Use the
list to review after an attempt, not to take the quiz.

<!-- QUESTIONS:START -->

## Questions

**1.** A colleague says a firewall works "at L3 and L4". What can such a firewall decide on?

- **A.** MAC addresses only
- **B.** IP addresses, protocols, and ports, but not HTTP paths
- **C.** HTTP paths and headers
- **D.** Only whether a cable is plugged in

**2.** In an Ethernet frame carrying a web request, which header comes first on the wire?

- **A.** The TCP header
- **B.** The IP header
- **C.** The Ethernet header
- **D.** The HTTP request line

**3.** Which tcpdump filter shows only traffic between the host 10.0.2.10 and port 53, in either direction?

- **A.** `host 10.0.2.10 and port 53`
- **B.** `10.0.2.10:53`
- **C.** `src 10.0.2.10 port 53 only`
- **D.** `ip 10.0.2.10 udp`

**4.** Which statement about MAC addresses on virtual interfaces (such as veth pairs) is true?

- **A.** They are burned in by the manufacturer
- **B.** They are generated randomly when the interface is created, and change when it is recreated
- **C.** They are always 00:00:00:00:00:00
- **D.** They are the same as the host's IP address

**5.** A switch has just been powered on, so its MAC table is empty. Host A sends a frame to host B. What happens to that frame?

- **A.** It is dropped until the switch learns B's address
- **B.** It is flooded out of every port except A's, and the switch learns A's port
- **C.** It is sent back to A
- **D.** The switch asks a DNS server where B is

**6.** Host A has never talked to B, which is on the same subnet. What is the very first packet A sends when you run `ping B`?

- **A.** An ICMP echo request to B's MAC address
- **B.** An ARP request broadcast asking who has B's IP address
- **C.** A DNS query
- **D.** A TCP SYN

**7.** `CKNE` On a node, `ip link show master cni0` lists four interfaces. What are they most likely?

- **A.** The node's physical network cards
- **B.** The node-side ends of the veth pairs of four Pods, attached to the bridge cni0
- **C.** Four VLANs
- **D.** Four routes

**8.** On one switch, host A's interface has MTU 1500 and host B's has MTU 1400. Small pings between them work. What fails?

- **A.** Nothing; the switch adjusts frame sizes automatically
- **B.** Packets bigger than 1400 bytes sent to B are dropped, so large transfers between A and B stall
- **C.** All traffic to A
- **D.** ARP between A and B

**9.** What is the broadcast address of `10.20.30.40/27`?

- **A.** 10.20.30.31
- **B.** 10.20.30.63
- **C.** 10.20.30.255
- **D.** 10.20.30.47

**10.** Which prefix length gives exactly 2 usable host addresses, as used on point-to-point links between routers?

- **A.** /24
- **B.** /29
- **C.** /30
- **D.** /32

**11.** `CKNE` A cluster's Pod CIDR is `10.244.0.0/16` and its Service CIDR is `10.96.0.0/12`. Do they overlap?

- **A.** Yes: 10.96.0.0/12 contains 10.244.0.0/16
- **B.** No: 10.96.0.0/12 covers 10.96.0.0 to 10.111.255.255, which does not include 10.244.x.x
- **C.** Yes: both start with 10
- **D.** It cannot be determined

**12.** A host has routes `default via 10.1.0.1` and `10.2.0.0/16 via 10.1.0.2`. Which gateway does a packet to `10.2.5.5` use, and why?

- **A.** 10.1.0.1, because the default route is checked first
- **B.** 10.1.0.2, because /16 is a longer (more specific) prefix than the default /0
- **C.** Both, alternately
- **D.** Neither; the packet is dropped

**13.** Why does `ip route add default via 10.5.0.2` fail on a host whose only address is `10.5.1.10/24`?

- **A.** Default routes need a /0 mask
- **B.** The gateway 10.5.0.2 is not on-link: it is outside every subnet the host is directly connected to
- **C.** Only routers can have default routes
- **D.** 10.5.0.2 is a broadcast address

**14.** `traceroute -n` to a host shows the same two routers repeating, `10.0.0.1`, `10.0.0.2`, `10.0.0.1`, `10.0.0.2`, until the hop limit. What is happening?

- **A.** The destination is down
- **B.** A routing loop: each router sends the packet to the other, until the TTL runs out
- **C.** The MTU is too small
- **D.** DNS is failing

**15.** A ping prints `From 192.168.9.1 icmp_seq=1 Destination Net Unreachable`. Which device should you inspect first?

- **A.** Your own host
- **B.** The router 192.168.9.1, which has no route to the destination's network
- **C.** The destination host
- **D.** The DNS server

**16.** `CKNE` Pods with private addresses must reach a partner's API, which only accepts connections from one fixed, known source address. Which mechanism provides that?

- **A.** DNAT on the partner's side
- **B.** SNAT on a chosen exit point, so traffic leaves with that exit point's address (an egress gateway)
- **C.** A larger MTU
- **D.** A CNAME record

**17.** Without NAT or extra routes, which statement about a host with a private address and an internet server is true?

- **A.** The server can reply, because private addresses are routed on the internet
- **B.** The request may reach the server, but the server has no route back to the private address, so no reply arrives
- **C.** Private addresses cannot send packets at all
- **D.** The server will reply over IPv6 instead

**18.** Which address is IPv6's equivalent of 127.0.0.1?

- **A.** fe80::1
- **B.** ::1
- **C.** ff02::1
- **D.** fd00::1

**19.** A client connects from `10.0.6.10:51544` to `10.0.6.20:443`. Which of these values was chosen by the client's kernel, not by any configuration?

- **A.** 443
- **B.** 51544
- **C.** 10.0.6.20
- **D.** All of them

**20.** In a capture of a TCP connection, which flag sequence shows the server refusing the connection?

- **A.** [S] then [S.]
- **B.** [S] then [R.]
- **C.** [P.] then [.]
- **D.** [F.] then [.]

**21.** `ss -tn` on a client shows a socket stuck in `SYN-SENT`. What does that mean?

- **A.** The connection is established and idle
- **B.** The client sent a SYN and has received no answer: the SYN or its reply is being lost or dropped
- **C.** The server refused the connection
- **D.** The connection is closing

**22.** A service must accept connections from other hosts. Which listening address is correct?

- **A.** 127.0.0.1:8080
- **B.** 0.0.0.0:8080
- **C.** localhost:8080
- **D.** 255.255.255.255:8080

**23.** Which protocol would you pick for a protocol that sends one small question and gets one small answer, where a lost answer is simply asked again?

- **A.** TCP, because it is reliable
- **B.** UDP, because it needs no connection setup and the application handles retries
- **C.** ICMP
- **D.** ARP

**24.** `curl` exits with code 28. What does that tell you?

- **A.** The connection was refused
- **B.** The operation timed out
- **C.** The server returned HTTP 500
- **D.** The certificate is invalid

**25.** `dig AAAA web.lab.internal` returns `status: NOERROR` with no answer, while `dig A web.lab.internal` returns an address. What does that mean?

- **A.** The name does not exist
- **B.** The name exists but has no IPv6 (AAAA) record
- **C.** The DNS server is broken
- **D.** IPv6 is blocked by a firewall

**26.** Which record type does Kubernetes publish so that clients can discover both the host and the port of a named Service port?

- **A.** A
- **B.** CNAME
- **C.** SRV
- **D.** PTR

**27.** `CKNE` A Pod's `/etc/resolv.conf` has `options ndots:5`. Writing which form of an external name avoids the search list completely?

- **A.** `api.github.com`
- **B.** `api.github.com.` (with a trailing dot)
- **C.** `API.GITHUB.COM`
- **D.** `https://api.github.com`

**28.** You changed a DNS record five minutes ago, but one client still gets the old address. The record had a TTL of 3600. What is the most likely explanation?

- **A.** The change failed
- **B.** A resolver cached the old answer and may keep it for up to an hour
- **C.** The client's MTU is wrong
- **D.** The client uses IPv6

**29.** `CKNE` A request through a Gateway returns `504 Gateway Timeout`. Where is the problem most likely?

- **A.** In the client's DNS
- **B.** In the backend behind the gateway, which did not answer in time
- **C.** In the client's TLS configuration
- **D.** In the Gateway's certificate

**30.** `CKNE` curl reports `SSL: no alternative certificate subject name matches target host name 'shop.example.com'`. What is wrong?

- **A.** The CA is not trusted
- **B.** The certificate has expired
- **C.** The certificate's SANs do not include shop.example.com
- **D.** The server's private key is wrong

**31.** `CKNE` Which file must never leave the CA, and is not needed by servers or clients for TLS to work?

- **A.** ca.crt
- **B.** ca.key
- **C.** server.crt
- **D.** server.csr

**32.** `CKNE` Two websites are hosted on one IP address with HTTPS. How does the server know which certificate to present before any HTTP has been exchanged?

- **A.** From the Host header
- **B.** From the SNI field in the TLS ClientHello
- **C.** From the client's IP address
- **D.** From DNS

**33.** `CKNE` Why do two containers in the same Kubernetes Pod reach each other on localhost?

- **A.** Kubernetes adds hosts file entries
- **B.** They share one network namespace, so they share the loopback interface
- **C.** kube-proxy forwards localhost traffic
- **D.** They run on the same node

**34.** `CKNE` Which command moves the interface `veth-x` into the network namespace `pod1`?

- **A.** ip netns add veth-x pod1
- **B.** ip link set veth-x netns pod1
- **C.** ip addr add veth-x dev pod1
- **D.** ip route add veth-x via pod1

**35.** `CKNE` Pods on the same node can talk to each other, but Pods on different nodes cannot. Which of these is NOT a likely cause?

- **A.** Missing routes between nodes for the other nodes' Pod subnets
- **B.** A firewall between nodes blocking the overlay's UDP port
- **C.** An application listening on 127.0.0.1
- **D.** A broken VXLAN tunnel configuration

**36.** `CKNE` In a capture on a node's main interface you see UDP packets to port 4789. What are they?

- **A.** DNS queries
- **B.** VXLAN overlay traffic carrying Pod packets between nodes
- **C.** BGP sessions
- **D.** kubelet health checks

**37.** `CKNE` Which netfilter hook sees packets that local programs on the host send, before the routing decision?

- **A.** PREROUTING
- **B.** INPUT
- **C.** OUTPUT
- **D.** FORWARD

**38.** `CKNE` On a node using kube-proxy in iptables mode, which command is the quickest way to see the rules for the Service with ClusterIP 10.96.0.10?

- **A.** ip route get 10.96.0.10
- **B.** iptables-save | grep 10.96.0.10
- **C.** ss -ltn | grep 10.96.0.10
- **D.** dig 10.96.0.10

**39.** You fixed a firewall rule and the error changed from `Connection timed out` to `Connection refused`. What is the right next step?

- **A.** Undo the fix, because the error is still there
- **B.** Check the listener on the target (ss -ltnp): packets now arrive, and nothing accepts them on that address and port
- **C.** Restart the router
- **D.** Check DNS

**40.** A request from a laptop to an app fails. Captures show the SYN leaving the laptop and arriving at the router, but never arriving at the app. Where is the fault?

- **A.** On the laptop
- **B.** Between the router and the app: the router's forwarding, filtering, or routes, or the app's link
- **C.** In the app's listener
- **D.** In DNS

<details>
<summary>Answers</summary>

**1. B.** L3 is the internet layer (IP addresses) and L4 the transport layer (TCP/UDP ports). Reading HTTP paths needs L7.

**2. C.** Encapsulation puts the outermost envelope first: Ethernet, then IP, then TCP, then the HTTP data.

**3. A.** BPF filters combine primitives with and, or, and not. host matches source or destination, and port matches TCP or UDP source or destination ports.

**4. B.** Virtual interfaces get random, locally administered MAC addresses. That is why lab MAC addresses differ between runs.

**5. B.** Unknown destinations are flooded. The switch learns from the source address of every frame, so A's location is learned right away and B's when B answers.

**6. B.** Before A can address a frame to B, it needs B's MAC address. ARP asks for it with a broadcast; the echo request follows once B replies.

**7. B.** Bridge-based CNI plugins attach one veth end per Pod to the node's bridge. `ip link show master <bridge>` lists the bridge's ports.

**8. B.** B refuses frames larger than its own MTU, and switches never resize frames. Every interface in a broadcast domain must use the same MTU; fix the odd one out.

**9. B.** A /27 has 32 addresses, so subnets start at multiples of 32: 40 falls in 32 to 63. The broadcast is the last address, 10.20.30.63.

**10. C.** A /30 has 4 addresses: network, two hosts, broadcast. A /32 is a single address.

**11. B.** A /12 spans 16 values in the second octet: 96 to 111. 244 is outside that range, so the two ranges are separate.

**12. B.** Longest prefix match: the most specific matching route wins, regardless of the order in which routes were added.

**13. B.** A host can only send to a gateway it can reach directly (ARP for). The next hop must be inside one of its connected subnets.

**14. B.** When two routers each point at the other for the same destination, packets bounce between them. The TTL stops them from circling forever.

**15. B.** The From address names the device that gave up. Net Unreachable means it had no matching route.

**16. B.** Source NAT rewrites the source address. Doing it on one designated node or gateway gives all egress traffic one predictable address, which is what egress gateways (Chapter 60) are for.

**17. B.** Private ranges are not routed on the internet. The edge router's source NAT is what makes replies possible.

**18. B.** ::1/128 is the IPv6 loopback address. fe80::/10 is link-local, ff02::1 is a multicast group, and fd00::/8 is the unique local (private) range.

**19. B.** 51544 is an ephemeral port picked for this one connection. 443 is the server's well-known port, and 10.0.6.20 the server's address.

**20. B.** A reset (R) in answer to a SYN is a refusal: nothing listens there, or a firewall rejects it. [S] then [S.] is an accepted connection.

**21. B.** SYN-SENT is the state while waiting for the SYN-ACK. If it lasts, nothing comes back: a route, a filter, or a dead host. A refusal would end the attempt at once.

**22. B.** 0.0.0.0 means every address the host has. 127.0.0.1 and localhost are loopback only.

**23. B.** This is DNS's reasoning. A TCP handshake would cost more than the question itself.

**24. B.** Exit code 28 is a timeout, 7 is a failed connection (refused or unreachable), and 60 is a certificate problem. HTTP errors exit 0 unless you add --fail.

**25. B.** NOERROR with an empty answer means the name exists without a record of that type. A missing name would be NXDOMAIN.

**26. C.** SRV records carry a target host and a port, for example _http._tcp.web.shop.svc.cluster.local.

**27. B.** A trailing dot makes the name fully qualified, so the resolver asks for exactly that name and skips the search domains.

**28. B.** Caches keep answers for their TTL. Lower the TTL well before a planned change.

**29. B.** 504 means the proxy reached out to the backend and gave up waiting. 502 is a bad answer, 503 no available backend.

**30. C.** Name mismatch: the certificate is valid but issued for other names. Trust problems say unable to get local issuer; expiry says certificate has expired.

**31. B.** The CA's private key signs certificates. Anyone holding it can issue trusted certificates for any name. Clients only need ca.crt.

**32. B.** The Host header is encrypted inside TLS, so it arrives too late. SNI carries the name in the unencrypted ClientHello.

**33. B.** A Pod is one network namespace. Containers on the same node but in different Pods do not share localhost.

**34. B.** `ip link set <interface> netns <namespace>` moves an interface between namespaces. Its configuration (addresses, state) is reset when it moves.

**35. C.** A loopback-only listener would fail for Pods on the same node too. The other three only affect traffic between nodes.

**36. B.** 4789 is the standard VXLAN port. tcpdump decodes the inner Pod packet for you.

**37. C.** Locally generated packets enter netfilter at OUTPUT, then pass routing and POSTROUTING. PREROUTING is for packets arriving from an interface.

**38. B.** The ClusterIP appears in the KUBE-SERVICES rule that jumps to the Service's KUBE-SVC chain. The address is on no interface, so ss and ip route show nothing useful.

**39. B.** The symptom moved up a layer, which is progress. Refused points at the listener.

**40. B.** Capture points split the path. The packet got as far as the router and no further, so the fault lies in the second half.

</details>

<!-- QUESTIONS:END -->
