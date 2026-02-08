output "cluster_id" {
  description = "The ID of the EKS cluster"
  value       = aws_eks_cluster.devops1.id
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = aws_eks_cluster.devops1.name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.devops1.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.devops1.vpc_config[0].cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.devops1.certificate_authority[0].data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = aws_eks_cluster.devops1.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for EKS"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "node_group_id" {
  description = "EKS node group ID"
  value       = aws_eks_node_group.devops1.id
}

output "node_group_status" {
  description = "Status of the EKS node group"
  value       = aws_eks_node_group.devops1.status
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.devops1_vpc.id
}

output "subnet_ids" {
  description = "List of subnet IDs"
  value       = aws_subnet.devops1_subnet[*].id
}

output "node_security_group_id" {
  description = "Security group ID for worker nodes"
  value       = aws_security_group.devops1_node_sg.id
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}
