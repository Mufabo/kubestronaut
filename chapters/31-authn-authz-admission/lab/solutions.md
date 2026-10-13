# Chapter 31 lab: solutions

Try each task before reading its solution. The commands below pass `-n` explicitly
where a Namespace is needed. The policy and binding are cluster-scoped.

## Task 1: a policy and a binding for ch31-apps

Write the policy and the binding as one manifest, and apply it:

```bash
kubectl apply -f - <<'YAML'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: ch31-require-team
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["deployments"]
  validations:
    - expression: "has(object.metadata.labels) && 'team' in object.metadata.labels"
      message: "Deployments need a team label"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: ch31-require-team-binding
spec:
  policyName: ch31-require-team
  validationActions: ["Deny"]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: ch31-apps
YAML
```

The `namespaceSelector` on the binding is what keeps the policy inside `ch31-apps`.
Without it, the policy would apply to every Deployment in the cluster. The
`has(...)` guard stops a Deployment with no labels at all from producing an error.
To test, run `kubectl -n ch31-apps apply --dry-run=server -f deployment.yaml`.

## Task 2: enforce restricted on ch31-restricted

```bash
kubectl label namespace ch31-restricted pod-security.kubernetes.io/enforce=restricted --overwrite
```

A privileged Pod is refused with `violates PodSecurity "restricted:latest"`. A Pod
with `runAsNonRoot: true`, `seccompProfile: RuntimeDefault`,
`allowPrivilegeEscalation: false`, and `capabilities.drop: ["ALL"]` is accepted.

## Task 3: a token for ci-bot

```bash
kubectl -n ch31-apps create token ci-bot --duration=1h > /tmp/ch31-token.txt
```

The check authenticates with a kubeconfig of its own, because `kubectl --token`
does not replace the client certificate in the admin kubeconfig.

## Task 4: a Role and RoleBinding for ci-bot

```bash
kubectl -n ch31-apps create role deployer --verb=create,get,list --resource=deployments.apps
kubectl -n ch31-apps create rolebinding ci-bot-deploys --role=deployer --serviceaccount=ch31-apps:ci-bot
kubectl auth can-i delete deployments.apps --as=system:serviceaccount:ch31-apps:ci-bot -n ch31-apps
```

The last command prints `no`. A Deployment from `ci-bot` without a `team` label
is still refused: RBAC allows the request, and then the policy from Task 1 refuses
it, with the policy's name in the message.

## Clean up

`make teardown CH=31` removes both Namespaces, the policy, the binding, and the token
file, and restores your kubectl context.
