variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "ssh_key_name" {
  description = "The name of the SSH key pair to use for instances"
  type        = string
  default     = "shack_keypair_1"
}

variable "ssh_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to nodes"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # WARNING: Change this to your specific IP for better security
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.33"
}

variable "ebs_csi_driver_version" {
  description = "Version of the EBS CSI driver addon"
  type        = string
  default     = "v1.50.1-eksbuild.1"
}

