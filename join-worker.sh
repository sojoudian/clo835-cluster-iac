#!/bin/bash
# CLO835 — join a worker to the cluster. Run on EACH worker (k8s-worker-1, k8s-worker-2).
#   ssh -i your-key.pem ubuntu@<worker public ip>
#   sudo bash join-worker.sh kubeadm join <master-private-ip>:6443 --token ... --discovery-token-ca-cert-hash sha256:...
#
# Paste the exact "kubeadm join ..." command that init-master.sh printed on the master.
set -euxo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: sudo bash join-worker.sh <the full 'kubeadm join ...' command from the master>"
  exit 1
fi

"$@"

echo "Joined. Check from the master with: kubectl get nodes"
