# Topology helpers for lab setup scripts. Runs INSIDE the netlab container.
# Lab scripts on the host send a script with `nl_script` (tools/lib.sh), which
# sources this file first. Every function is idempotent where it can be, and
# fails loudly (set -e in the caller) where it cannot.
#
# Vocabulary used throughout Part V:
#   host    a network namespace that plays one computer (h1, web, client, ...)
#   switch  a network namespace holding a Linux bridge named br0
#   router  a host with IP forwarding switched on
#   wire    a veth pair: a virtual cable with one end in each namespace

# host <name>...   create namespaces with loopback up and an empty resolver
host() {
  local n
  for n in "$@"; do
    ip netns add "$n"
    # IPv6 is off unless a lab asks for it (NETLAB_IPV6=1), so that beginners
    # see one address per interface. Chapter 40 switches it on.
    if [[ "${NETLAB_IPV6:-0}" != 1 ]]; then
      ip netns exec "$n" sysctl -qw net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1
    fi
    ip -n "$n" link set lo up
    mkdir -p "/etc/netns/${n}"
    # ip netns exec bind-mounts /etc/netns/<name>/* over /etc/*, so each host
    # gets its own resolv.conf and hosts file (Chapter 43).
    : > "/etc/netns/${n}/resolv.conf"
    printf '127.0.0.1\tlocalhost\n' > "/etc/netns/${n}/hosts"
  done
}

# router <name>...   a host that forwards packets between its interfaces
router() {
  local n
  for n in "$@"; do
    host "$n"
    ip netns exec "$n" sysctl -qw net.ipv4.ip_forward=1
  done
}

# switch <name>...   a namespace with a bridge br0 (the switch's backplane)
switch() {
  local n
  for n in "$@"; do
    host "$n"
    ip -n "$n" link add br0 type bridge
    ip -n "$n" link set br0 up
  done
}

# wire <nsA> <ifA> <nsB> <ifB> [down]
# A veth pair from nsA:ifA to nsB:ifB, both ends up unless "down" is given.
wire() {
  local a=$1 ia=$2 b=$3 ib=$4 state=${5:-up}
  ip link add "tmpa$$" type veth peer name "tmpb$$"
  ip link set "tmpa$$" netns "$a" name "$ia"
  ip link set "tmpb$$" netns "$b" name "$ib"
  if [[ "$state" == up ]]; then
    ip -n "$a" link set "$ia" up
    ip -n "$b" link set "$ib" up
  fi
}

# plug <host> <if> <switch> [port-name] [down]
# Cable host:if into the switch; the switch end joins br0.
plug() {
  local h=$1 ifc=$2 sw=$3 port=${4:-"${1}-${2}"} state=${5:-up}
  wire "$h" "$ifc" "$sw" "$port" "$state"
  ip -n "$sw" link set "$port" master br0
}

# addr <ns> <if> <cidr>...
addr() {
  local ns=$1 ifc=$2; shift 2
  local c
  for c in "$@"; do ip -n "$ns" addr add "$c" dev "$ifc"; done
}

# route <ns> <prefix|default> via <gw> [more ip-route args]
route() { local ns=$1; shift; ip -n "$ns" route add "$@"; }

# daemon <ns> <name> <command...>
# Start a long-running program inside a namespace, detached from this shell.
# Its PID goes to /run/netlab/<name>.pid and its output to
# /var/log/netlab/<name>.log. Restarting an existing daemon replaces it.
daemon() {
  local ns=$1 name=$2; shift 2
  stop_daemon "$name"
  ip netns exec "$ns" setsid "$@" >"/var/log/netlab/${name}.log" 2>&1 < /dev/null &
  echo $! > "/run/netlab/${name}.pid"
}

# stop_daemon <name>
stop_daemon() {
  local f="/run/netlab/${1}.pid"
  if [[ -f "$f" ]]; then
    kill "$(cat "$f")" 2>/dev/null || true
    rm -f "$f"
  fi
}

# web <ns> <name> <port> [bind-address] [message]
# A tiny HTTP server that answers every GET with a one-line page naming
# itself, so labs can tell which backend answered.
web() {
  local ns=$1 name=$2 port=$3 bind=${4:-0.0.0.0} msg=${5:-"hello from ${2}"}
  mkdir -p "/srv/${name}"
  printf '%s\n' "$msg" > "/srv/${name}/index.html"
  daemon "$ns" "$name" python3 -m http.server "$port" --bind "$bind" --directory "/srv/${name}"
}

# wait_port <ns> <port> [proto]   wait (up to 10 s) until something listens
wait_port() {
  local ns=$1 port=$2 proto=${3:-tcp} flag=-ltn i
  [[ "$proto" == udp ]] && flag=-lun
  for ((i = 0; i < 50; i++)); do
    ip netns exec "$ns" ss -H "$flag" "sport = :${port}" | grep -q . && return 0
    sleep 0.2
  done
  echo "topo: nothing is listening on ${proto}/${port} in ${ns}" >&2
  return 1
}

# topology   read a diagram from stdin; `topo` shows it to the reader
topology() { cat > /etc/netlab/topology.txt; }

# answers <chapter>   create (empty) the answer folder for a chapter's lab
answers() { rm -rf "/root/answers/${1}"; mkdir -p "/root/answers/${1}"; }
