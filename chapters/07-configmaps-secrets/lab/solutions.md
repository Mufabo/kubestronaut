# Chapter 07 lab: solutions

Try each task before reading its solution. The commands below assume `kubectl`
defaults to `ch07-config` (run `make use-namespace CH=7` once). Otherwise, add
`-n ch07-config` to every command.

## Task 1: create `app-config`

```bash
kubectl create configmap app-config --from-literal=LOG_LEVEL=info --from-literal=FEATURE_FLAG=on
kubectl get configmap app-config -o yaml
```

`--from-literal` sets each key exactly. Check the output: the keys are
`FEATURE_FLAG` and `LOG_LEVEL`, and `FEATURE_FLAG` is quoted in the YAML so that
YAML does not read it as a boolean.

## Task 2: create `db-credentials` from `legacy-db`

The password is random and stored only in the Secret `legacy-db`. Read it, and
pass it on:

```bash
pw="$(kubectl get secret legacy-db -o jsonpath='{.data.password}' | base64 -d)"
kubectl create secret generic db-credentials --from-literal=username=app --from-literal=password="$pw"
```

`kubectl create secret generic` gives the `Opaque` type. Do not copy the
encoded value into `--from-literal`: it would store the base64 text itself, not
the password. Also avoid `echo "$pw" | ...`, which adds a newline to the value.

## Task 3: run `web` with environment variables

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: web
spec:
  containers:
    - name: web
      image: nginx:1.27
      envFrom:
        - configMapRef:
            name: app-config
      env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
YAML
kubectl wait --for=condition=Ready pod/web --timeout=120s
```

`envFrom` imports every key of `app-config` at once. `env` with `valueFrom`
reads one key of the Secret. Confirm with `kubectl exec web -- env`.

## Task 4: the `reporter` Pod and the downward API

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: reporter
spec:
  containers:
    - name: reporter
      image: busybox:1.36
      command: ["sleep", "3600"]
      resources:
        limits:
          memory: 64Mi
      env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: MEM_LIMIT
          valueFrom:
            resourceFieldRef:
              containerName: reporter
              resource: limits.memory
              divisor: 1Mi
YAML
kubectl wait --for=condition=Ready pod/reporter --timeout=120s
kubectl exec reporter -- env | grep -E '^(POD_NAME|NODE_NAME|MEM_LIMIT)='
```

`fieldRef` reads Pod fields; `resourceFieldRef` reads container resources.
Without `divisor: 1Mi`, `MEM_LIMIT` would be `67108864` (bytes).

## Task 5: mount the configuration as files

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: config-viewer
spec:
  containers:
    - name: viewer
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: config
          mountPath: /etc/app
        - name: creds
          mountPath: /etc/db
          readOnly: true
  volumes:
    - name: config
      configMap:
        name: app-config
    - name: creds
      secret:
        secretName: db-credentials
YAML
kubectl wait --for=condition=Ready pod/config-viewer --timeout=120s
```

The ConfigMap is one file per key, so `/etc/app/LOG_LEVEL` holds `info`. The
Secret mount is read-only, which the check tests on the Pod spec, because a
writable mount would still show the right content.

## Why these checks accept any correct method

Each check reads the outcome: the objects in the cluster, the Pod spec's
references where the task asks for a reference rather than a literal value,
and the values a running container prints. You can create the ConfigMap with
YAML, with `kubectl create`, or with `kubectl edit`. The checks do not care.
