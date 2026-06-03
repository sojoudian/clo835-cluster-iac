#!/bin/bash
# CLO835 — full deploy runbook for a 3-node kubeadm cluster on AWS Learner Lab.
# This is a REFERENCE you follow step by step (it mixes your Mac, the master, and the workers).
# Do NOT run it all at once. IPs come from the `terraform apply` output and change every deploy.

############################################################
# ON YOUR MAC
############################################################

# --- 1. Confirm AWS credentials work ---
aws sts get-caller-identity
# expect: JSON with "Account": "505677385339" and role "voclabs".
# If you get ExpiredToken / InvalidClientTokenId -> re-paste a fresh [default] block
# from the Learner Lab "AWS Details -> AWS CLI" into ~/.aws/credentials.

# --- 2. Go to the Terraform folder ---
cd clo835-cluster-iac

# --- 3. Initialise + sanity-check ---
terraform init        # expect: "Terraform has been successfully initialized!"  (first time only)
terraform fmt         # expect: prints filenames it reformats (or nothing)
terraform validate    # expect: "Success! The configuration is valid."
terraform plan        # expect: "Plan: 16 to add, 0 to change, 0 to destroy."

# --- 4. Create the infrastructure ---
terraform apply       # review, then type: yes
# expect: "Apply complete! Resources: 16 added".
# Outputs print public_ips and private_ips for master / worker-1 / worker-2.
# Copy those IPs — you need them below.

# --- 5. (one-time) protect your key ---
chmod 400 your-key.pem

# --- 6. Confirm the boot bootstrap finished on each node (no SSH) ---
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=k8s-*" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].[Tags[?Key=='Name']|[0].Value,InstanceId]" --output text
# expect: the 3 instance names + IDs. Then per instance ID:
# aws ec2 get-console-output --instance-id i-XXXX --latest --output text | grep "Prerequisites installed"
#   expect: "Prerequisites installed. Next: run init-master.sh ..."  (may take ~2 min to appear)

# --- 7. Copy the cluster scripts up to the nodes ---
scp -i your-key.pem init-master.sh ubuntu@<MASTER_PUBLIC_IP>:~
scp -i your-key.pem join-worker.sh ubuntu@<WORKER1_PUBLIC_IP>:~
scp -i your-key.pem join-worker.sh ubuntu@<WORKER2_PUBLIC_IP>:~
# expect: each file transfers (100%).

############################################################
# ON THE MASTER  (ssh -i your-key.pem ubuntu@<MASTER_PUBLIC_IP>)
############################################################

# --- 8. (optional) confirm prerequisites locally ---
# cloud-init status --wait        # expect: status: done
# kubeadm version                 # expect: v1.31.x
# systemctl is-active containerd  # expect: active

# --- 9. Initialise the control plane ---
bash init-master.sh
# expect: "Your Kubernetes control-plane has initialized successfully!",
#         Flannel objects created, and a printed "kubeadm join ..." command.
# COPY that join command.

############################################################
# ON EACH WORKER  (ssh -i your-key.pem ubuntu@<WORKERx_PUBLIC_IP>)
############################################################

# --- 10. Join the cluster (paste the command the master printed) ---
sudo bash join-worker.sh kubeadm join <MASTER_PRIVATE_IP>:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
# expect: "This node has joined the cluster."

############################################################
# BACK ON THE MASTER
############################################################

# --- 11. Verify the cluster ---
kubectl get nodes -o wide
# expect: 3 nodes, all STATUS Ready (1 control-plane + 2 <none> workers). Workers may take ~30-60s.

# --- 12. (optional) run the Week-05 lab ---
bash commands.sh        # or step through it section by section

############################################################
# (optional) USE kubectl FROM YOUR MAC
############################################################
# scp -i your-key.pem ubuntu@<MASTER_PUBLIC_IP>:~/.kube/config ./kubeconfig
# then edit kubeconfig: change the server line to  https://<MASTER_PUBLIC_IP>:6443
# export KUBECONFIG=$PWD/kubeconfig ; kubectl get nodes   # expect: same 3 Ready nodes

############################################################
# TEAR DOWN  (ON YOUR MAC)
############################################################

# --- 13. Destroy everything when done (stops the $50 meter) ---
cd clo835-cluster-iac
terraform destroy       # type: yes
# expect: "Destroy complete! Resources: 16 destroyed."
# To PAUSE instead of destroy: stop the instances in EC2 (keeps the cluster, ~$0 compute while stopped).
