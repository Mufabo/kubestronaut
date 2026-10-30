# A Deployment whose history setup builds one revision at a time (shop, history).
# __NAME__, __REPLICAS__, __IMAGE__, and __CAUSE__ are filled in by setup.sh.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: __NAME__
  labels: {app: __NAME__}
  annotations:
    kubernetes.io/change-cause: "__CAUSE__"
spec:
  replicas: __REPLICAS__
  progressDeadlineSeconds: 30
  selector:
    matchLabels: {app: __NAME__}
  template:
    metadata:
      labels: {app: __NAME__}
    spec:
      containers:
        - name: web
          image: __IMAGE__
          resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 100m, memory: 64Mi}}
