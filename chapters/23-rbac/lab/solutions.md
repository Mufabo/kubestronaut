# Chapter 23 lab: solutions

Try each task before reading its solution. The commands below pass
`-n ch23-rbac` explicitly, because the lab does not change your default namespace.

## Task 1: the `reporter` ServiceAccount and its Role

```bash
kubectl -n ch23-rbac create serviceaccount reporter
kubectl -n ch23-rbac create role pod-reader --verb=get,list --resource=pods
kubectl -n ch23-rbac create rolebinding reporter-reads-pods --role=pod-reader --serviceaccount=ch23-rbac:reporter
kubectl auth can-i delete pods --as=system:serviceaccount:ch23-rbac:reporter -n ch23-rbac
```

The Role's verbs are `get` and `list`, so the last command prints `no`.

## Task 2: read nodes with a ClusterRole

```bash
kubectl create clusterrole ch23-node-viewer --verb=get,list --resource=nodes
kubectl create clusterrolebinding ch23-reporter-nodes --clusterrole=ch23-node-viewer --serviceaccount=ch23-rbac:reporter
kubectl auth can-i list nodes --as=system:serviceaccount:ch23-rbac:reporter
```

Nodes are cluster-scoped, so the rule is a ClusterRole, bound with a ClusterRoleBinding.

## Task 3: a Pod that calls the API as `reporter`

```bash
cat <<'YAML' | kubectl -n ch23-rbac apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: probe
spec:
  serviceAccountName: reporter
  containers:
    - name: probe
      image: curlimages/curl:8.11.1
      command: ["sleep", "3600"]
YAML
kubectl -n ch23-rbac wait --for=condition=Ready pod/probe --timeout=180s
kubectl -n ch23-rbac exec probe -- sh -c 'curl -s -o /dev/null -w "%{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/ch23-rbac/pods'
kubectl -n ch23-rbac exec probe -- sh -c 'curl -s -o /dev/null -w "%{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -X DELETE -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/ch23-rbac/pods/probe'
```

The first request prints `200`, and the second prints `403`. The image is pinned, and
busybox's `wget` cannot complete the TLS handshake with the API server, so the lab uses curl.

## Task 4: a ServiceAccount whose token is not mounted

```bash
kubectl -n ch23-rbac patch serviceaccount builder -p '{"automountServiceAccountToken":false}'
cat <<'YAML' | kubectl -n ch23-rbac apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: quiet
spec:
  serviceAccountName: builder
  containers:
    - name: quiet
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML
kubectl -n ch23-rbac exec quiet -- test -e /var/run/secrets/kubernetes.io/serviceaccount/token || echo "no token"
```

The ServiceAccount's setting sets the default for its Pods, and no token file is
mounted.

## Task 5: the answer file

```bash
kubectl auth can-i delete pods --as=system:serviceaccount:ch23-rbac:reporter -n ch23-rbac > /tmp/ch23-can-delete.txt
```

## Why these checks accept any correct method

Each check reads what Kubernetes decides: `kubectl auth can-i` for an identity, the
stored Role and bindings, the status codes a Pod gets from the API, the
ServiceAccount's and Pod's token settings, and the answer file. You can create the
objects with YAML or imperative commands, and the checks do not care which.
