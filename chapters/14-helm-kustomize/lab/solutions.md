# Chapter 14 lab: solutions

Try each task before reading its solution. The commands below assume you run
them from the repository root. They pass `-n ch14-helm` explicitly, because the
lab does not change your default namespace. The chart is at
`lab/.state/charts/shop` and the Kustomize sources at `lab/.state/kustomize`.

## Task 1: install `shop`

```bash
helm install shop chapters/14-helm-kustomize/lab/.state/charts/shop -n ch14-helm --set replicaCount=2
helm status shop -n ch14-helm
```

`--set replicaCount=2` changes the chart's default of 1. The first revision holds
those values.

## Task 2: upgrade the tag, keep the replicas

```bash
helm upgrade shop chapters/14-helm-kustomize/lab/.state/charts/shop -n ch14-helm --reuse-values --set image.tag=1.27
helm get values shop -n ch14-helm --revision 2
```

Without `--reuse-values`, the upgrade would fall back to the chart's default of
one replica. With it, `replicaCount: 2` carries over, and `--set` replaces only
the tag.

## Task 3: roll back to revision 1

```bash
helm rollback shop 1 -n ch14-helm
helm history shop -n ch14-helm
```

The rollback is a new revision (3), and its description reads `Rollback to 1`.
The Deployment runs `nginx:1.26` again.

## Task 4: apply the Kustomize overlay

```bash
kubectl kustomize chapters/14-helm-kustomize/lab/.state/kustomize/overlay
kubectl -n ch14-helm apply -k chapters/14-helm-kustomize/lab/.state/kustomize/overlay
```

Read the rendered output first. The overlay sets three replicas, the image
`nginx:1.27`, and the label `env: prod` on the Deployment.

## Task 5: the `greeter` release

```bash
helm install greeter chapters/14-helm-kustomize/lab/.state/charts/shop -n ch14-helm --set greeting=hello
kubectl -n ch14-helm get configmap greeter-config -o jsonpath='{.data.greeting}{"\n"}'
```

The template names the ConfigMap after the release, so it is `greeter-config`,
and its `greeting` key comes from `--set`.

## Why these checks accept any correct method

Each check reads what Helm and Kubernetes record: the history and the stored
values of each revision (`helm history`, `helm get values --revision`), the live
Deployments and ConfigMaps, and the release status. You can install with
`--set`, with a values file (`-f`), or by editing the chart's values, and the
checks do not care which.
