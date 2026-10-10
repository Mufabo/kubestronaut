# Namespace p1-ganymede, question 16: setup applies one revision at a time.
# __IMAGE__ and __CAUSE__ are filled in by setup.sh.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: atlas
  labels: {app: atlas}
  annotations:
    kubernetes.io/change-cause: "__CAUSE__"
spec:
  replicas: 3
  progressDeadlineSeconds: 30
  selector:
    matchLabels: {app: atlas}
  template:
    metadata:
      labels: {app: atlas}
    spec:
      containers:
        - name: web
          image: __IMAGE__
          resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 100m, memory: 64Mi}}
