# CLO835 — Kubernetes cluster on AWS (Terraform + commands)

Infrastructure-as-code that builds a **3-node Kubernetes cluster** (1 control plane + 2 workers, kubeadm) on AWS Academy Learner Lab EC2 instances, plus the lab commands used in class.

The cluster forms itself: each node installs the prerequisites at boot, the master runs `kubeadm init`, the workers join automatically, and Flannel CNI is applied. No manual init/join needed.

## Install the tools

| Tool | Install guide |
|------|---------------|
| AWS CLI v2 | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |
| Terraform | https://developer.hashicorp.com/terraform/install |
| kubectl | https://kubernetes.io/docs/tasks/tools/ |
| Git | https://git-scm.com/downloads |

## Prerequisites

- AWS Academy Learner Lab access
- An EC2 **key pair** in the Learner Lab (for SSH)

## 1. Get your AWS credentials

In the Learner Lab page, click **Start Lab**, wait for the green dot, then **AWS Details → AWS CLI → Show**. Copy the `[default]` block and paste it into `~/.aws/credentials`:

```ini
[default]
aws_access_key_id=...
aws_secret_access_key=...
aws_session_token=...
```

Set the region once in `~/.aws/config`:

```ini
[default]
region=us-east-1
```

These credentials **rotate every session** (max ~4 hours) — re-paste a fresh `[default]` block each session. Verify with `aws sts get-caller-identity`.

## 2. Set your key pair

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars and set key_name to YOUR EC2 key pair name
```

Download that key pair's `.pem` (Learner Lab AWS Details, or EC2 > Key Pairs) and `chmod 400 your-key.pem`.

## 3. Build the cluster

```bash
terraform init
terraform apply        # type: yes
```

Wait ~3–5 minutes while the nodes self-configure. Outputs print the master/worker IPs.

## 4. Use the cluster

```bash
ssh -i your-key.pem ubuntu@<master-public-ip>
kubectl get nodes -o wide          # masternode + workernode1 + workernode2, all Ready
```

## 5. Run the lab

`commands.sh` holds the in-class commands (Pods, manifests, sidecars, labels, namespaces, ReplicaSets, lifecycle). Run them one at a time on the master.

> The lab manifests reference `maziar/kubia:0.1`. Replace that with your own image (see the separate `kubia` app repo), or use `luksa/kubia` for a quick test.

## Cleanup

```bash
terraform destroy      # type: yes  — stops the $50 budget meter
```

## Files

| File | Purpose |
|------|---------|
| `main.tf`, `variables.tf` | the cluster (2 security groups, 3 EC2 instances) |
| `bootstrap.sh` | runs on every node — installs containerd + kubeadm prerequisites |
| `master-init.sh.tftpl` | master: `kubeadm init` + Flannel + label workers |
| `worker-join.sh.tftpl` | workers: auto-join the cluster |
| `init-master.sh`, `join-worker.sh` | manual fallback (if you build the cluster by hand) |
| `runbook.sh` | full step-by-step deploy reference |
| `commands.sh` | the in-class lab commands |
| `*.yaml` | lab manifests (Pod, sidecar, ReplicaSet, Deployment) |
