# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # variables come from the sourcing script and lab.env
# Part single: cp1 and two workers, from the prereqs snapshot. Sourced by common.sh.

part_setup() {
  require_snapshot "$LAB_SNAPSHOT"
  [[ "$(hostname)" == cp1 ]] || die "run this lab on cp1 (envs/vagrant/kbook-vm ssh)"
  if sudo test -e /etc/kubernetes/admin.conf; then
    die "a cluster already exists on cp1. To start over, restore the snapshot on the host: envs/vagrant/kbook-vm restore ${LAB_SNAPSHOT}"
  fi
  local node
  for node in node1 node2; do
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$node" true || die "cannot ssh to ${node} from cp1"
  done
  info "Lab ready: containerd and kubeadm ${K8S_VERSION} are installed on cp1, node1, and node2; no cluster exists yet."
}

# Task 1: kubeadm init with the requested address, Pod network, and version
t1() {
  local cfg
  sudo test -e /etc/kubernetes/admin.conf &&
  cfg="$(ak -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}')" &&
  grep -q "podSubnet: ${POD_CIDR}" <<<"$cfg" &&
  grep -q "kubernetesVersion: ${K8S_VERSION}" <<<"$cfg" &&
  sudo grep -q -- "--advertise-address=${CP_IP}" /etc/kubernetes/manifests/kube-apiserver.yaml
}

# Task 2: kubectl works for you (the vagrant user) through the context kbook-vm
t2() {
  [[ "$(kubectl config current-context 2>/dev/null)" == "$LAB_CONTEXT" ]] &&
  kubectl get nodes >/dev/null
}

# Task 3: Calico runs on every node and uses the requested Pod network
t3() {
  local want ready cidr
  want="$(ak get nodes -o name | wc -l | tr -d '[:space:]')" &&
  ready="$(ak -n kube-system get daemonset calico-node -o jsonpath='{.status.numberReady}')" &&
  [[ "$want" -ge 1 && "$ready" == "$want" ]] &&
  cidr="$(ak get ippools.crd.projectcalico.org -o jsonpath='{.items[*].spec.cidr}')" &&
  [[ "$cidr" == "$POD_CIDR" ]] &&
  [[ "$(ak get node cp1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" == "True" ]]
}

# Task 4: node1 and node2 have joined, and all three nodes are Ready at the pinned version
t4() {
  local rows
  rows="$(ak get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.status.nodeInfo.kubeletVersion} {.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}')" &&
  [[ "$rows" == "$(printf 'cp1 %s True\nnode1 %s True\nnode2 %s True' "$K8S_VERSION" "$K8S_VERSION" "$K8S_VERSION")" ]]
}

# Task 5: the workers carry the worker role label (and the control plane does not)
t5() {
  local n1 n2 cp
  n1="$(ak get node node1 -o jsonpath='{.metadata.labels}')" &&
  n2="$(ak get node node2 -o jsonpath='{.metadata.labels}')" &&
  cp="$(ak get node cp1 -o jsonpath='{.metadata.labels}')" &&
  [[ "$n1" == *'"node-role.kubernetes.io/worker":""'* ]] &&
  [[ "$n2" == *'"node-role.kubernetes.io/worker":""'* ]] &&
  [[ "$cp" != *'node-role.kubernetes.io/worker'* ]]
}

part_verify() {
  require_snapshot "$LAB_SNAPSHOT"
  check 1 "the control plane on cp1 was initialized with ${CP_IP}, ${POD_CIDR}, and ${K8S_VERSION}" \
    "kubeadm init --apiserver-advertise-address --pod-network-cidr --kubernetes-version (and NumCPU on a one-CPU VM)" t1
  check 2 "kubectl works for the vagrant user, with the current context named ${LAB_CONTEXT}" \
    "copy /etc/kubernetes/admin.conf to ~/.kube/config, chown it, then kubectl config rename-context" t2
  check 3 "Calico runs on every node with the IP pool ${POD_CIDR}, and cp1 is Ready" \
    "Calico's manifest defaults to 192.168.0.0/16; set CALICO_IPV4POOL_CIDR before applying it" t3
  check 4 "node1 and node2 have joined; all three nodes are Ready at ${K8S_VERSION}" \
    "kubeadm token create --print-join-command on cp1, then run the result with sudo on each worker" t4
  check 5 "node1 and node2 have the role label node-role.kubernetes.io/worker (and cp1 does not)" \
    "kubectl label node NAME node-role.kubernetes.io/worker=" t5
}

part_solve() {
  require_snapshot "$LAB_SNAPSHOT"
  # Task 1: on a one-CPU VM, kubeadm's two-CPU check has to be skipped
  local preflight=() join node
  (($(nproc) < 2)) && preflight=(--ignore-preflight-errors=NumCPU)
  sudo kubeadm init --apiserver-advertise-address="$CP_IP" --pod-network-cidr="$POD_CIDR" \
    --kubernetes-version="$K8S_VERSION" "${preflight[@]}" >/dev/null

  # Task 2
  user_kubeconfig

  # Task 3: the manifest's pool defaults to 192.168.0.0/16, which contains the VM network
  install_calico

  # Task 4
  join="$(sudo kubeadm token create --print-join-command)"
  for node in node1 node2; do
    # shellcheck disable=SC2029  # the join command is meant to expand here, on cp1
    ssh "$node" "sudo ${join}" >/dev/null
  done
  kubectl wait --for=condition=Ready node --all --timeout=600s >/dev/null
  wait_calico 3

  # Task 5
  kubectl label node node1 node2 node-role.kubernetes.io/worker= >/dev/null
}
