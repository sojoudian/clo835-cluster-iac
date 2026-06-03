#!/bin/bash
# CLO835 — initialize the Kubernetes control plane. Run on the MASTER (k8s-master).
#   ssh -i your-key.pem ubuntu@<master public ip>
#   bash init-master.sh
set -euxo pipefail

# Auto-detect this node's IPs from EC2 metadata (IMDSv2)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)

# Create the control plane.
#  - advertise on the PRIVATE IP (how workers reach it)
#  - add the PUBLIC IP to the API cert so you can use kubectl from your laptop
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address="$PRIVATE_IP" \
  --apiserver-cert-extra-sans="$PUBLIC_IP"

# Set up kubectl for the ubuntu user
mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# Install the Flannel CNI (pod network)
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

echo
echo "=================================================================="
echo "Control plane ready. Run THIS on each worker (with sudo):"
echo "------------------------------------------------------------------"
kubeadm token create --print-join-command
echo "=================================================================="
echo "To use kubectl from your laptop: copy ~/.kube/config off this node"
echo "and change the server line to https://$PUBLIC_IP:6443"
