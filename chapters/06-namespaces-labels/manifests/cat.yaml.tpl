# A small Pod for the colour namespaces (Task 1). __NAME__ is filled in by setup.sh.
apiVersion: v1
kind: Pod
metadata:
  name: __NAME__
  labels: {app: pets}
spec:
  terminationGracePeriodSeconds: 1   # busybox sleep ignores SIGTERM
  containers:
    - name: pet
      image: busybox:1.36
      command: ["sleep", "3600"]
      resources: {requests: {cpu: 5m, memory: 8Mi}, limits: {cpu: 50m, memory: 32Mi}}
