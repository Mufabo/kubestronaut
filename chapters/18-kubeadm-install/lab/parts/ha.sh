# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2153,SC2329,SC2029  # variables come from lab.env; functions go to wait_for by name; ssh arguments expand on cp1
# Part ha: three control plane nodes behind the HAProxy load balancer on lb, from
# the ha-prereqs snapshot (kbook-vm build-ha, then kbook-vm restore-ha). node1 and
# node2 are halted. Sourced by common.sh.

HA_SNAPSHOT="${LAB_SNAPSHOT_ha}"
MANIFESTS_DIR=/etc/kubernetes/manifests
OFF_DIR=/etc/kubernetes/manifests-off
declare -A CP_IPS=([cp1]=192.168.56.10 [cp2]=192.168.56.13 [cp3]=192.168.56.14)

# etcdctl inside cp1's etcd Pod, with etcd's own client certificate.
etcd_exec() {
  ak -n kube-system exec etcd-cp1 -- etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key "$@" 2>&1
}

part_setup() {
  require_snapshot "$HA_SNAPSHOT"
  [[ "$(hostname)" == cp1 ]] || die "run this lab on cp1 (envs/vagrant/kbook-vm ssh)"
  if sudo test -e /etc/kubernetes/admin.conf; then
    die "a cluster already exists on cp1. To start over, restore the snapshot on the host: envs/vagrant/kbook-vm restore-ha"
  fi
  local vm
  for vm in cp2 cp3 lb; do
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$vm" true || die "cannot ssh to ${vm} from cp1 (on the host: kbook-vm restore-ha)"
  done
  [[ "$(ssh lb systemctl is-active haproxy 2>/dev/null)" == active ]] || die "HAProxy does not run on lb; restore ha-prereqs on the host: envs/vagrant/kbook-vm restore-ha"
  info "Lab ready: cp1, cp2, and cp3 have containerd and kubeadm ${K8S_VERSION}; lb (${LB_IP}) balances port 6443 over them. No cluster exists yet."
}

# Task 1: init on cp1 with the load balancer as the control plane endpoint
t1() {
  local cfg server sans
  sudo test -e /etc/kubernetes/admin.conf || return 1
  cfg="$(ak -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' 2>/dev/null)" || return 1
  grep -q "controlPlaneEndpoint: ${LB_IP}:6443" <<<"$cfg" || return 1
  grep -q "podSubnet: ${POD_CIDR}" <<<"$cfg" || return 1
  grep -q "kubernetesVersion: ${K8S_VERSION}" <<<"$cfg" || return 1
  server="$(ak config view -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)"
  [[ "$server" == "https://${LB_IP}:6443" ]] || return 1
  sans="$(sudo openssl x509 -noout -ext subjectAltName -in /etc/kubernetes/pki/apiserver.crt 2>/dev/null)"
  [[ "$sans" == *"IP Address:${LB_IP}"* ]]
}

# Task 2: Calico on every node, with the requested pool
t2() {
  local want ready cidr
  want="$(ak get nodes -o name 2>/dev/null | grep -c .)"
  ready="$(ak -n kube-system get daemonset calico-node -o jsonpath='{.status.numberReady}' 2>/dev/null)"
  # After Task 4, cp3 is NotReady, and its Calico Pod cannot report ready either.
  if ssh cp3 "sudo test -f ${OFF_DIR}/kube-apiserver.yaml" 2>/dev/null; then want=$((want - 1)); fi
  [[ "$want" -ge 1 && "$ready" -ge "$want" ]] || return 1
  cidr="$(ak get ippools.crd.projectcalico.org -o jsonpath='{.items[*].spec.cidr}' 2>/dev/null)"
  [[ "$cidr" == "$POD_CIDR" ]] || return 1
  [[ "$(ak get node cp1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == True ]]
}

# Task 3: cp2 and cp3 joined as control plane nodes; three API servers and etcd members
t3() {
  local rows members apiservers cp3_down=false
  # Task 4 takes cp3's control plane down on purpose. Its kubelet talks to its
  # own API server, so cp3 then turns NotReady, and its old Pods stay listed.
  ssh cp3 "sudo test -f ${OFF_DIR}/kube-apiserver.yaml" && cp3_down=true
  rows="$(ak get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{range .items[*]}{.metadata.name} {.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null)"
  if $cp3_down; then
    [[ "$rows" == $'cp1 True\ncp2 True\ncp3 '* ]] || return 1
  else
    [[ "$rows" == $'cp1 True\ncp2 True\ncp3 True' ]] || return 1
  fi
  apiservers="$(ak -n kube-system get pods -l component=kube-apiserver -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | LC_ALL=C sort)"
  [[ "$apiservers" == $'cp1\ncp2\ncp3' ]] || { $cp3_down && [[ "$apiservers" == $'cp1\ncp2' ]]; } || return 1
  members="$(etcd_exec member list)" || return 1
  [[ "$(grep -c ', started, ' <<<"$members")" == 3 ]]
}

# Task 4: cp3's control plane is down, and the cluster still works through lb
t4() {
  local health
  ssh cp3 "sudo test -f ${OFF_DIR}/kube-apiserver.yaml && sudo test -f ${OFF_DIR}/etcd.yaml && ! sudo test -f ${MANIFESTS_DIR}/kube-apiserver.yaml && ! sudo test -f ${MANIFESTS_DIR}/etcd.yaml" || return 1
  ak get --raw /readyz >/dev/null 2>&1 || return 1
  health="$(etcd_exec endpoint health --cluster)"
  [[ "$(grep -c ' is healthy' <<<"$health")" == 2 && "$(grep -c ' is unhealthy' <<<"$health")" == 1 ]] || return 1
  [[ "$(etcd_exec member list | grep -c ', started, ')" == 3 ]]
}

part_verify() {
  require_snapshot "$HA_SNAPSHOT"
  check 1 "cp1 was initialized with the control plane endpoint ${LB_IP}:6443, ${POD_CIDR}, and ${K8S_VERSION}; kubeconfigs and certificates use the endpoint" \
    "kubeadm init --control-plane-endpoint ${LB_IP}:6443 --upload-certs --apiserver-advertise-address ${CP_IP} ..." t1
  check 2 "Calico runs on every node with the IP pool ${POD_CIDR}, and cp1 is Ready" \
    "as in Part single: CALICO_IPV4POOL_CIDR in the manifest" t2
  check 3 "cp1, cp2, and cp3 are Ready control plane nodes, each with an API server and a started etcd member" \
    "the control plane join command kubeadm init printed, plus --apiserver-advertise-address NODE-IP and --ignore-preflight-errors=NumCPU,Mem" t3
  check 4 "cp3's API server and etcd manifests are in ${OFF_DIR}; the API answers through lb, and etcd has 2 of 3 members healthy" \
    "on cp3: sudo mv the static Pod manifests; etcdctl endpoint health --cluster" t4
}

part_solve() {
  require_snapshot "$HA_SNAPSHOT"
  local preflight=() join key vm
  (($(nproc) < 2)) && preflight=(--ignore-preflight-errors=NumCPU)

  # Task 1: init prints the control plane join command, with a certificate key
  # that is valid for two hours.
  local init_out
  init_out="$(sudo kubeadm init --control-plane-endpoint="${LB_IP}:6443" --upload-certs \
    --apiserver-advertise-address="$CP_IP" --pod-network-cidr="$POD_CIDR" \
    --kubernetes-version="$K8S_VERSION" "${preflight[@]}" 2>&1)"
  key="$(sed -n 's/.*--certificate-key \([a-f0-9]\{64\}\).*/\1/p' <<<"$init_out" | head -1)"
  [[ -n "$key" ]] || die "kubeadm init printed no certificate key"
  user_kubeconfig

  # Task 2
  install_calico

  # Task 3: join both with init's key. cp2 and cp3 have 1.5 GB, below kubeadm's
  # 1700 MB minimum for a control plane node, so the joins skip that check too.
  join="$(sudo kubeadm token create --print-join-command)"
  for vm in cp2 cp3; do
    # shellcheck disable=SC2029  # the join command is meant to expand here, on cp1
    ssh "$vm" "sudo ${join} --control-plane --certificate-key ${key} --apiserver-advertise-address ${CP_IPS[$vm]} --ignore-preflight-errors=NumCPU,Mem" >/dev/null
  done
  kubectl wait --for=condition=Ready node --all --timeout=900s >/dev/null
  wait_calico 3
  three_apiservers() { [[ "$(kubectl -n kube-system get pods -l component=kube-apiserver -o name | grep -c .)" == 3 ]]; }
  wait_for "three API servers" 600 three_apiservers

  # Task 4
  ssh cp3 "sudo mkdir -p ${OFF_DIR} && sudo mv ${MANIFESTS_DIR}/*.yaml ${OFF_DIR}/"
  one_unhealthy() {
    local h
    h="$(etcd_exec endpoint health --cluster)"
    [[ "$(grep -c ' is unhealthy' <<<"$h")" == 1 ]]
  }
  wait_for "cp3's etcd member to be unhealthy" 300 one_unhealthy
}
