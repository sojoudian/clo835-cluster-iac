provider "aws" {
  region = "us-east-1"
}

locals {
  # kubeadm bootstrap token shared by the master (--token) and the workers (--token),
  # so workers can join automatically without copying anything from the master.
  # Format: 6 chars "." 16 chars, lowercase letters + digits. Lab-only — rotate if you like.
  k8s_token = "abcdef.0123456789abcdef"
}

# Latest Ubuntu 24.04 LTS (Noble), x86_64, from Canonical
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

########################################################
# Security groups
########################################################
resource "aws_security_group" "master" {
  name        = "k8s-master"
  description = "Kubernetes control-plane node"
}

resource "aws_security_group" "worker" {
  name        = "k8s-worker"
  description = "Kubernetes worker nodes"
}

# --- Node-to-node: allow ALL traffic between cluster nodes ---
# Covers the component ports without enumerating each:
#   etcd 2379-2380, kubelet 10250, kube-scheduler 10259,
#   kube-controller-manager 10257, kube-proxy 10256,
#   API 6443 (node->node), Flannel VXLAN 8472/UDP.
resource "aws_security_group_rule" "master_from_self" {
  type              = "ingress"
  security_group_id = aws_security_group.master.id
  self              = true
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
}
resource "aws_security_group_rule" "master_from_worker" {
  type                     = "ingress"
  security_group_id        = aws_security_group.master.id
  source_security_group_id = aws_security_group.worker.id
  protocol                 = "-1"
  from_port                = 0
  to_port                  = 0
}
resource "aws_security_group_rule" "worker_from_self" {
  type              = "ingress"
  security_group_id = aws_security_group.worker.id
  self              = true
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
}
resource "aws_security_group_rule" "worker_from_master" {
  type                     = "ingress"
  security_group_id        = aws_security_group.worker.id
  source_security_group_id = aws_security_group.master.id
  protocol                 = "-1"
  from_port                = 0
  to_port                  = 0
}

# --- Master external inbound ---
resource "aws_security_group_rule" "master_ssh" {
  type              = "ingress"
  security_group_id = aws_security_group.master.id
  description       = "SSH"
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = ["0.0.0.0/0"]
}
resource "aws_security_group_rule" "master_api" {
  type              = "ingress"
  security_group_id = aws_security_group.master.id
  description       = "Kubernetes API server"
  protocol          = "tcp"
  from_port         = 6443
  to_port           = 6443
  cidr_blocks       = ["0.0.0.0/0"]
}

# --- Worker external inbound ---
resource "aws_security_group_rule" "worker_ssh" {
  type              = "ingress"
  security_group_id = aws_security_group.worker.id
  description       = "SSH"
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = ["0.0.0.0/0"]
}
resource "aws_security_group_rule" "worker_https" {
  type              = "ingress"
  security_group_id = aws_security_group.worker.id
  description       = "App / HTTPS"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["0.0.0.0/0"]
}
resource "aws_security_group_rule" "worker_nodeport" {
  type              = "ingress"
  security_group_id = aws_security_group.worker.id
  description       = "NodePort Services"
  protocol          = "tcp"
  from_port         = 30000
  to_port           = 32767
  cidr_blocks       = ["0.0.0.0/0"]
}

# --- Egress: allow all (both) ---
resource "aws_security_group_rule" "master_egress" {
  type              = "egress"
  security_group_id = aws_security_group.master.id
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}
resource "aws_security_group_rule" "worker_egress" {
  type              = "egress"
  security_group_id = aws_security_group.worker.id
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}

########################################################
# Instances: master + 2 workers (cluster forms automatically at boot)
########################################################
resource "aws_instance" "master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "m5.large" # 2 vCPU / 8 GB (steady, non-burstable)
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.master.id]

  root_block_device {
    volume_size = 32
  }

  # bootstrap.sh (prereqs) + templated kubeadm init
  user_data = "${file("${path.module}/bootstrap.sh")}\n${templatefile("${path.module}/master-init.sh.tftpl", { k8s_token = local.k8s_token })}"

  tags = {
    Name = "k8s-master"
  }
}

resource "aws_instance" "worker" {
  count                  = 2
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "m5.large"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.worker.id]

  root_block_device {
    volume_size = 32
  }

  # bootstrap.sh (prereqs) + templated kubeadm join (waits/retries until the master API is up)
  user_data = "${file("${path.module}/bootstrap.sh")}\n${templatefile("${path.module}/worker-join.sh.tftpl", {
    k8s_token = local.k8s_token
    master_ip = aws_instance.master.private_ip
    node_name = "workernode${count.index + 1}"
  })}"

  tags = {
    Name = "k8s-worker-${count.index + 1}"
  }
}

output "public_ips" {
  value = merge(
    { master = aws_instance.master.public_ip },
    { for i, w in aws_instance.worker : "worker-${i + 1}" => w.public_ip }
  )
}

output "private_ips" {
  value = merge(
    { master = aws_instance.master.private_ip },
    { for i, w in aws_instance.worker : "worker-${i + 1}" => w.private_ip }
  )
}
