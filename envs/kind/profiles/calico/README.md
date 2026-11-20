# Profile `calico`

The default profile, and the cluster that `make cluster` builds: Calico
(`CALICO_VERSION`) as the CNI, so NetworkPolicy is enforced, with pod CIDR
192.168.0.0/16, plus metrics-server (`METRICS_SERVER_VERSION`) for `kubectl top`
and the HPA. Every Tier 1 lab of Parts I to IV and every Tier 1 mock exam runs
on it (labs without `LAB_PROFILE` in `lab.env`).
