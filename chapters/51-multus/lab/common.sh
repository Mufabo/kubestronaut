# shellcheck shell=bash
# Helpers shared by the Chapter 51 lab scripts (sourced after lib.sh and lab.env).

# install_cni_plugins   copy the reference plugins that Multus delegates to
# (macvlan, ipvlan, bridge, static) into /opt/cni/bin on every node. The
# release tarball is downloaded once into lab/.state and checked against the
# SHA-256 in versions.env.
install_cni_plugins() {
  local here=$1 tgz tmp node b
  tgz="${here}/.state/cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz"
  mkdir -p "${here}/.state"
  if [[ ! -f "$tgz" ]]; then
    curl -fsSLo "${tgz}.part" "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz" ||
      die "could not download the CNI plugins ${CNI_PLUGINS_VERSION}"
    mv "${tgz}.part" "$tgz"
  fi
  echo "${CNI_PLUGINS_SHA256}  ${tgz}" | sha256sum --check --status ||
    { rm -f "$tgz"; die "the CNI plugins tarball does not match CNI_PLUGINS_SHA256; run setup again"; }
  tmp="$(mktemp -d)"
  tar -xzf "$tgz" -C "$tmp" ./macvlan ./ipvlan ./bridge ./static
  for node in $(kind_nodes); do
    for b in macvlan ipvlan bridge static; do docker cp "${tmp}/${b}" "${node}:/opt/cni/bin/${b}" >/dev/null; done
  done
  rm -rf "$tmp"
}

# first_cni_conf <node>   the name of the configuration file the runtime uses
first_cni_conf() {
  docker exec "$1" sh -c 'ls -1 /etc/cni/net.d 2>/dev/null | grep -E "\.(conf|conflist|json)$" | sort | head -n1' 2>/dev/null
}
