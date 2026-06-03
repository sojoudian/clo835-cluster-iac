#!/bin/bash
# CLO835 Week-05 lab — Pods, sidecars, labels, ReplicaSets, namespaces, lifecycle.
# Run on the MASTER, section by section (not all at once — the cleanup at the end removes everything).

# ---- 0. Verify the cluster (3 nodes: 1 control-plane + 2 workers) ----
kubectl get nodes -o wide

# ---- Generate a Pod manifest from the CLI (deck: kubia-manual) ----
# --dry-run=client creates nothing — it just renders the YAML into the file.
kubectl run kubia --image=maziar/kubia:0.1 --dry-run=client -o yaml > kubia-manual.yaml
kubectl apply -f kubia-manual.yaml                  # now create the pod from the manifest
kubectl get pod kubia

# ---- A. Multi-container Pod (main + sidecar) ----
cat > pod-sidecar.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: web-sidecar
  labels: { app: web, tier: frontend }
spec:
  containers:
    - name: web                 # main container (serves on :8080)
      image: maziar/kubia:0.1
      ports: [{ containerPort: 8080 }]
    - name: sidecar             # sidecar
      image: busybox
      command: ["/bin/sh","-c","sleep 3600"]
EOF
kubectl apply -f pod-sidecar.yaml
kubectl get pod web-sidecar -o wide                 # 2/2 Running, on a worker node
kubectl exec web-sidecar -c sidecar -- wget -qO- localhost:8080  # sidecar reaches kubia on shared localhost
kubectl logs web-sidecar -c web                     # -c picks a container in a multi-container pod

# ---- B. Labels & selectors ----
kubectl get pods --show-labels
kubectl get pods -l app=web
kubectl label pod web-sidecar env=demo
kubectl get pods -l env=demo
kubectl label pod web-sidecar env-                  # trailing - removes the label

# ---- C. ReplicaSet from a manifest ----
cat > rs.yaml <<'EOF'
apiVersion: apps/v1
kind: ReplicaSet
metadata: { name: web-rs }
spec:
  replicas: 3
  selector: { matchLabels: { app: web-rs } }
  template:
    metadata: { labels: { app: web-rs } }
    spec:
      containers:
        - name: kubia
          image: maziar/kubia:0.1
          ports: [{ containerPort: 8080 }]
EOF
kubectl apply -f rs.yaml
kubectl get pods -l app=web-rs -o wide               # pods SPREAD across worker-1 & worker-2
kubectl delete $(kubectl get pod -l app=web-rs -o name | head -1)   # (no extra 'pod' — -o name already prints pod/<name>)
kubectl get pods -l app=web-rs                       # ReplicaSet self-heals back to 3
kubectl scale rs web-rs --replicas=5
kubectl get rs web-rs

# ---- D. Namespaces (scoping) ----
kubectl create namespace dev
kubectl apply -f rs.yaml -n dev
kubectl get rs,pods -n dev
kubectl get pods --all-namespaces | grep web-rs      # same name coexists in default and dev

# ---- E. Pod lifecycle / restart policy ----
kubectl run done --image=busybox --restart=Never -- /bin/sh -c "echo hello; exit 0"
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/done --timeout=60s
kubectl get pod done                                 # → Completed / Succeeded
kubectl run fail --image=busybox --restart=Never -- /bin/sh -c "exit 1"
sleep 8
kubectl get pod fail                                 # → Error (phase Failed)

# ---- F. Cleanup ----
kubectl delete pod web-sidecar done fail
kubectl delete rs web-rs
kubectl delete namespace dev
kubectl get all                                      # only the default 'kubernetes' service remains
