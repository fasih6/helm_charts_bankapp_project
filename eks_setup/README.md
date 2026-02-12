# EKS Cluster Terraform Setup

This Terraform configuration creates a production-ready Amazon EKS (Elastic Kubernetes Service) cluster with all necessary networking, security, and IAM resources.

## Architecture Overview

This setup creates:
- **VPC** with DNS support enabled
- **2 Public Subnets** across different availability zones
- **Internet Gateway** for public internet access
- **EKS Cluster** running Kubernetes 1.31
- **Node Group** with 3 t3.medium instances
- **EBS CSI Driver** for persistent volume support
- **OIDC Provider** for IAM roles for service accounts (IRSA)
- **Security Groups** for cluster and worker nodes

## Prerequisites

Before you begin, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform**
3. **kubectl** installed for cluster management
4. **An AWS SSH Key Pair** created in your target region (default: `shack_keypair_1`)
5. **Appropriate IAM permissions** to create VPC, EKS, IAM, and EC2 resources

## File Structure

```
.
├── main.tf           # Main infrastructure resources
├── variables.tf      # Input variables
├── outputs.tf        # Output values
├── versions.tf       # Provider version constraints
└── README.md         # This file
```

## Quick Start

### 1. Clone or Download Configuration Files

Place all `.tf` files in the same directory.

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review and Customize Variables

Edit `variables.tf` or create a `terraform.tfvars` file:

```hcl
aws_region             = "us-east-1"
ssh_key_name           = "your-key-pair-name"
ssh_allowed_cidr_blocks = ["YOUR_IP/32"]  # Replace with your IP
kubernetes_version     = "1.31"
```

**Security Note:** Change `ssh_allowed_cidr_blocks` from `0.0.0.0/0` to your specific IP address for better security.

### 4. Plan the Deployment

```bash
terraform plan
```

### 5. Deploy the Infrastructure

```bash
terraform apply
```

Type `yes` when prompted to confirm.

### 6. Configure kubectl

Once the cluster is created, configure kubectl to connect:

```bash
aws eks update-kubeconfig --region us-east-1 --name devops1-cluster
```

### 7. Verify the Cluster

```bash
kubectl get nodes
kubectl get pods -A
```

## 6) Install Ingress‑NGINX controller (v1.13.2) - (Optional)

```bash
kubectl apply -f \
  https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.13.2/deploy/static/provider/cloud/deploy.yaml

kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller

# Verify
kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx get svc ingress-nginx-controller
```

> Once `EXTERNAL-IP`/hostname is assigned on the `ingress-nginx-controller` Service, note it for DNS.

---

### Install cert‑manager (v1.19.0) - (Optional)

```bash
kubectl apply -f \
  https://github.com/cert-manager/cert-manager/releases/download/v1.19.0/cert-manager.yaml

# Wait for all three deployments
kubectl -n cert-manager rollout status deploy/cert-manager
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector
kubectl -n cert-manager rollout status deploy/cert-manager-webhook

# Verify
kubectl -n cert-manager get pods
```

> Optional next step: create a ClusterIssuer (Let’s Encrypt HTTP‑01) and an Ingress with TLS annotations.

---

###  Quick verification cheatsheet

```bash
# Nodes ready?
kubectl get nodes -o wide

# Ingress controller LB hostname
kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo

# cert-manager webhook healthy?
kubectl -n cert-manager get deploy -o wide
```

---

## Configuration Details

### Network Configuration

- **VPC CIDR:** 10.0.0.0/16
- **Subnet 1:** 10.0.0.0/24 (AZ: us-east-1a)
- **Subnet 2:** 10.0.1.0/24 (AZ: us-east-1b)
- Both subnets are public with auto-assigned public IPs

### EKS Cluster

- **Name:** devops1-cluster
- **Kubernetes Version:** 1.31 (configurable)
- **Endpoint Access:** Both public and private enabled
- **Node Group:**
  - Instance Type: t3.medium
  - Desired Capacity: 3 nodes
  - Min/Max Size: 3 nodes

### Security Groups

**Cluster Security Group:**
- Allows all outbound traffic
- Managed by EKS for control plane communication

**Node Security Group:**
- Nodes can communicate with each other (all protocols)
- Allows traffic from control plane (ports 1025-65535)
- Allows HTTPS from control plane (port 443)
- SSH access (port 22) from specified CIDR blocks

### IAM Roles

1. **Cluster Role:** Allows EKS service to manage resources
2. **Node Group Role:** Allows worker nodes to:
   - Join the cluster
   - Use ECR for container images
   - Manage networking (CNI)
3. **EBS CSI Driver Role:** Enables persistent volume provisioning

## Variables Reference

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `ssh_key_name` | EC2 key pair name | `shack_keypair_1` | Yes |
| `ssh_allowed_cidr_blocks` | CIDR blocks for SSH access | `["0.0.0.0/0"]` | No |
| `kubernetes_version` | Kubernetes version | `1.31` | No |
| `ebs_csi_driver_version` | EBS CSI driver version | `v1.37.0-eksbuild.1` | No |

## Outputs

After successful deployment, Terraform outputs:

- `cluster_name` - EKS cluster name
- `cluster_endpoint` - API server endpoint
- `cluster_certificate_authority_data` - CA certificate (sensitive)
- `cluster_oidc_issuer_url` - OIDC provider URL
- `vpc_id` - VPC identifier
- `subnet_ids` - List of subnet IDs
- `region` - Deployment region

View outputs:
```bash
terraform output
```

## Scaling the Cluster

To modify node count, update `variables.tf` or your `terraform.tfvars`:

```hcl
# In main.tf, modify the scaling_config block
scaling_config {
  desired_size = 5
  max_size     = 10
  min_size     = 3
}
```

Then run:
```bash
terraform apply
```

## The Real-World DevOps Workflow:
**Problem**: Terraform and Kubernetes both manage AWS resources, but Kubernetes can create resources (like Load Balancers, EBS volumes, or ALBs) outside Terraform’s control. When you ran terraform destroy, Terraform deleted the cluster first, but leftover Kubernetes-created resources blocked deletion of subnets, IGWs, etc., causing the destroy to fail.

**Solution / Best Practice**: Always delete Kubernetes-managed resources before running terraform destroy.
```bash
# 1. Deploy infrastructure
terraform apply

# 2. Configure kubectl
aws eks update-kubeconfig --name devops1-cluster --region us-east-1

# 3. Deploy your Kubernetes apps
kubectl apply -f my-app.yaml

# 4. When you want to destroy:
# FIRST: Clean up Kubernetes resources
kubectl delete -f my-app.yaml
kubectl delete svc --all -A
kubectl delete pvc --all -A

# Wait for AWS cleanup
sleep 60

# THEN: Destroy Terraform infrastructure
terraform destroy
```
## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning:** This will permanently delete your cluster and all associated resources.

## Cost Considerations

Estimated monthly costs (us-east-1):
- **EKS Cluster:** ~$73/month
- **3x t3.medium nodes:** ~$100/month (24/7)
- **Data transfer and EBS volumes:** Variable
- **Total:** ~$175-200/month

Reduce costs by:
- Using smaller instance types
- Reducing node count
- Implementing cluster autoscaling
- Using Spot instances for non-critical workloads

## Troubleshooting

### Nodes not joining cluster

Check node IAM role permissions:
```bash
kubectl get nodes
aws eks describe-nodegroup --cluster-name devops1-cluster --nodegroup-name devops1-node-group
```

### Cannot connect with kubectl

Update kubeconfig:
```bash
aws eks update-kubeconfig --region us-east-1 --name devops1-cluster --profile your-profile
```

### EBS volumes not provisioning

Verify CSI driver is running:
```bash
kubectl get pods -n kube-system | grep ebs-csi
kubectl get csidrivers
```

## Security Best Practices

1. **Restrict SSH access:** Update `ssh_allowed_cidr_blocks` to your IP only
2. **Enable private endpoint only:** Set `endpoint_public_access = false` for production
3. **Use IAM roles for service accounts (IRSA):** Already configured via OIDC provider
4. **Enable cluster logging:** Add logging configuration to EKS cluster resource
5. **Use secrets encryption:** Configure KMS encryption for secrets
6. **Regular updates:** Keep Kubernetes version and addons up to date

## Additional Resources

- [Amazon EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [EBS CSI Driver](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)

## License

This configuration is provided as-is for educational and production use.

## Support

For issues with:
- **Terraform:** Check [Terraform AWS Provider Issues](https://github.com/hashicorp/terraform-provider-aws/issues)
- **EKS:** Consult [AWS Support](https://aws.amazon.com/support/)
- **This Configuration:** Review logs and verify IAM permissions

---

**Note:** Always review and test infrastructure changes in a development environment before applying to production.
