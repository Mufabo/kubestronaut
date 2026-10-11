# Chapter 16 lab: solutions

Try each task before reading its solution. The commands below pass
`-n ch16-delivery` explicitly, because the lab does not change your default
namespace. Task 1 needs Docker and the `kind` command on your machine.

## Task 1: build and load `ch16-app:1.0`

```bash
docker build -t ch16-app:1.0 chapters/16-images-delivery/lab/.state/app
kind load docker-image ch16-app:1.0 --name kbook
docker exec kbook-worker crictl images | grep ch16-app
```

`docker build` reads the Dockerfile in `lab/.state/app`, which pins `nginx:1.27-alpine`
and writes `hello from ch16` to the page. `kind load` copies the image to every
node, so the worker has it without a registry.

## Task 2: the `app` Deployment

```bash
cat <<'YAML' | kubectl -n ch16-delivery apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
    spec:
      containers:
        - name: app
          image: ch16-app:1.0
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 80
YAML
kubectl -n ch16-delivery rollout status deployment/app
kubectl -n ch16-delivery exec deploy/app -- wget -qO- http://localhost/
```

`IfNotPresent` uses the copy on the node. With `Always`, the kubelet would try
to pull `ch16-app:1.0` from a registry, and the Pod would fail.

## Task 3: `legacy` with the Recreate strategy

```bash
kubectl -n ch16-delivery patch deployment legacy --type=merge -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}'
kubectl -n ch16-delivery rollout status deployment/legacy
```

`rollingUpdate: null` removes the field, because `Recreate` does not take it.

## Task 4: the rolling update of `app`

```bash
kubectl -n ch16-delivery patch deployment app --type=merge -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxUnavailable":0,"maxSurge":1}}}}'
```

With `maxUnavailable: 0`, no old Pod is removed until its replacement is ready.

## Task 5: the `regcred` Secret and `private-app`

```bash
kubectl -n ch16-delivery create secret docker-registry regcred --docker-server=registry.example.test --docker-username=ci --docker-password=not-a-real-token
cat <<'YAML' | kubectl -n ch16-delivery apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: private-app
spec:
  imagePullSecrets:
    - name: regcred
  containers:
    - name: app
      image: registry.example.test/team/app:1.0
YAML
```

The Pod stays in `ImagePullBackOff`, because the registry does not exist. The
check reads its specification, which is correct.

## Why these checks accept any correct method

The checks read what is stored and running: the image on the worker node, the
Deployments' images, pull policy, replicas and strategy, the Secret's type, and the
Pod's `imagePullSecrets`. You can build the image with any tool that produces the
tag, and you can make each change with `patch`, `apply`, or `edit`.
