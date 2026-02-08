provider "aws" {
  region = var.aws_region
}

# VPC
resource "aws_vpc" "devops1_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "devops1-vpc"
  }
}

# Subnets
resource "aws_subnet" "devops1_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.devops1_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.devops1_vpc.cidr_block, 8, count.index)
  availability_zone       = element(["${var.aws_region}a", "${var.aws_region}b"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "devops1-subnet-${count.index}"
    "kubernetes.io/cluster/devops1-cluster"     = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "devops1_igw" {
  vpc_id = aws_vpc.devops1_vpc.id

  tags = {
    Name = "devops1-igw"
  }
}

# Route Table
resource "aws_route_table" "devops1_route_table" {
  vpc_id = aws_vpc.devops1_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.devops1_igw.id
  }

  tags = {
    Name = "devops1-route-table"
  }
}

# Route Table Association
resource "aws_route_table_association" "devops1_association" {
  count          = 2
  subnet_id      = aws_subnet.devops1_subnet[count.index].id
  route_table_id = aws_route_table.devops1_route_table.id
}

# Cluster Security Group
resource "aws_security_group" "devops1_cluster_sg" {
  name_prefix = "devops1-cluster-sg-"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.devops1_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "devops1-cluster-sg"
  }
}

# Node Security Group
resource "aws_security_group" "devops1_node_sg" {
  name_prefix = "devops1-node-sg-"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.devops1_vpc.id

  # Allow nodes to communicate with each other
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Allow nodes to receive communication from the cluster control plane
  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.devops1_cluster_sg.id]
  }

  # Allow pods to communicate with the cluster API Server
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.devops1_cluster_sg.id]
  }

  # SSH access (optional - restrict to your IP)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name                                        = "devops1-node-sg"
    "kubernetes.io/cluster/devops1-cluster"     = "owned"
  }
}

# Allow cluster to communicate with nodes
resource "aws_security_group_rule" "cluster_to_node" {
  type                     = "egress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.devops1_cluster_sg.id
  source_security_group_id = aws_security_group.devops1_node_sg.id
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "devops1_cluster_role" {
  name = "devops1-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "devops1_cluster_role_policy" {
  role       = aws_iam_role.devops1_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# IAM Role for Node Group
resource "aws_iam_role" "devops1_node_group_role" {
  name = "devops1-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "devops1_node_group_role_policy" {
  role       = aws_iam_role.devops1_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "devops1_node_group_cni_policy" {
  role       = aws_iam_role.devops1_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "devops1_node_group_registry_policy" {
  role       = aws_iam_role.devops1_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# EKS Cluster
resource "aws_eks_cluster" "devops1" {
  name     = "devops1-cluster"
  role_arn = aws_iam_role.devops1_cluster_role.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = aws_subnet.devops1_subnet[*].id
    security_group_ids      = [aws_security_group.devops1_cluster_sg.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.devops1_cluster_role_policy,
  ]

  tags = {
    Name = "devops1-cluster"
  }
}

# OIDC Provider for EKS
data "tls_certificate" "eks" {
  url = aws_eks_cluster.devops1.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.devops1.identity[0].oidc[0].issuer

  tags = {
    Name = "devops1-eks-oidc"
  }
}

# IAM Role for EBS CSI Driver
data "aws_iam_policy_document" "ebs_csi_driver_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  name               = "devops1-ebs-csi-driver-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# EBS CSI Driver Addon
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.devops1.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = var.ebs_csi_driver_version
  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.devops1
  ]
}

# EKS Node Group
resource "aws_eks_node_group" "devops1" {
  cluster_name    = aws_eks_cluster.devops1.name
  node_group_name = "devops1-node-group"
  node_role_arn   = aws_iam_role.devops1_node_group_role.arn
  subnet_ids      = aws_subnet.devops1_subnet[*].id

  scaling_config {
    desired_size = 3
    max_size     = 3
    min_size     = 3
  }

  instance_types = ["t3.medium"]

  remote_access {
    ec2_ssh_key               = var.ssh_key_name
    source_security_group_ids = [aws_security_group.devops1_node_sg.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.devops1_node_group_role_policy,
    aws_iam_role_policy_attachment.devops1_node_group_cni_policy,
    aws_iam_role_policy_attachment.devops1_node_group_registry_policy,
  ]

  tags = {
    Name = "devops1-node-group"
  }
}
