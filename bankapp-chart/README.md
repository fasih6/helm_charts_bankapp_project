# BankApp Deployment Guide

## Prerequisites Checklist

Before deploying, ensure you have:

- [ ] EKS cluster running and accessible
- [ ] kubectl configured (run `kubectl cluster-info`)
- [ ] Helm 3.x installed (run `helm version`)
- [ ] EBS CSI driver installed on EKS cluster
- [ ] AWS credentials configured
- [ ] Appropriate IAM permissions

## Deployment Steps

### Step 1: Prepare Your EKS Cluster

First, apply your Terraform configuration to create the EKS cluster:

```bash
cd terraform/
terraform init
terraform plan
terraform apply

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name devops1-cluster
```

### Step 2: Verify EBS CSI Driver

```bash
# Check if EBS CSI driver is installed
kubectl get pods -n kube-system | grep ebs-csi

# If not present, it should be added via Terraform EKS addon
# Verify the addon
aws eks describe-addon --cluster-name devops1-cluster --addon-name aws-ebs-csi-driver
```

### Step 3: Prepare Helm Chart

Navigate to your Helm chart directory:

```bash
cd helm/bankapp-chart/
```

### Step 4: Validate the Chart

```bash
# Lint the chart
helm lint .

# Dry-run to check templates
helm install bankapp . --dry-run --debug
```

### Step 5: Deploy to Development

```bash
# Using the deployment script
./deploy.sh dev install

# Or manually
kubectl create namespace dev
helm install bankapp . -f values.yaml -n dev
```

### Step 6: Verify Deployment

```bash
# Check release status
helm status bankapp --namespace dev

# Check all resources
kubectl get all -n dev

# Check pods are running
kubectl get pods -n dev
watch kubectl get pods -n dev

# Check PVC is bound
kubectl get pvc -n dev

# Check services
kubectl get svc -n dev
```

## Upgrade Process

### Upgrade Development

```bash
# Modify values-dev.yaml or templates as needed
./deploy.sh dev upgrade

3 Or
helm upgrade bankapp . -f values.yaml -n dev
```

## Rollback

If something goes wrong:

```bash
# List releases
helm list -n prod

# Check history
helm history bankapp -n prod

# Rollback to previous version
helm rollback bankapp -n prod

# Rollback to specific revision
helm rollback bankapp 2 -n prod
```

## Monitoring and Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n prod
kubectl describe pod <pod-name> -n prod
```

### Check Logs

```bash
# MySQL logs
kubectl logs -l app=mysql -n prod

# BankApp logs
kubectl logs -l app=bankapp -n prod -f

# All containers in a pod
kubectl logs <pod-name> -n prod --all-containers
```

### Check Events

```bash
kubectl get events -n prod --sort-by='.lastTimestamp'
```

### Check PVC

```bash
kubectl get pvc -n prod
kubectl describe pvc mysql-pvc -n prod
```

### Test MySQL Connection

```bash
kubectl run mysql-client --rm -it --restart=Never --image=mysql:8 -n prod \
  -- mysql -h mysql-service -u root -pTest@123 bankappdb
```

### Check Service Endpoints

```bash
kubectl get endpoints -n prod
kubectl describe svc bankapp-service -n prod
```

## Common Issues and Solutions

### Issue 1: Pods Stuck in Pending

**Symptoms:** Pods remain in `Pending` state

**Solutions:**
```bash
# Check events
kubectl describe pod <pod-name> -n prod

# Common causes:
# 1. Insufficient resources
kubectl describe nodes

# 2. PVC not bound
kubectl get pvc -n prod

# 3. Storage class not available
kubectl get storageclass
```

### Issue 2: MySQL Pod CrashLoopBackOff

**Symptoms:** MySQL pod keeps restarting

**Solutions:**
```bash
# Check logs
kubectl logs -l app=mysql -n prod --previous

# Common causes:
# 1. PVC permission issues
# 2. Incorrect password format
# 3. Insufficient resources

# Delete PVC and redeploy
kubectl delete pvc mysql-pvc -n prod
helm uninstall bankapp -n prod
helm install bankapp . -f values-prod.yaml -n prod
```

### Issue 3: BankApp Can't Connect to MySQL

**Symptoms:** BankApp logs show connection errors

**Solutions:**
```bash
# Verify MySQL service
kubectl get svc mysql-service -n prod

# Check if MySQL is ready
kubectl get pods -l app=mysql -n prod

# Verify connection from BankApp pod
kubectl exec -it <bankapp-pod> -n prod -- sh
nc -zv mysql-service 3306
```

### Issue 4: LoadBalancer Not Getting External IP

**Symptoms:** LoadBalancer service shows `<pending>` for external IP

**Solutions:**
```bash
# Check AWS Load Balancer Controller is installed
kubectl get pods -n kube-system | grep aws-load-balancer

# Check service events
kubectl describe svc bankapp-service -n prod

# Verify security groups allow traffic
# Check AWS Load Balancer in AWS Console
```

## Cleanup

### Remove Development Environment

```bash
./deploy.sh dev uninstall

# Delete PVC
kubectl delete pvc mysql-pvc -n dev

# Delete namespace
kubectl delete namespace dev
```

### Remove Production Environment

```bash
./deploy.sh prod uninstall

# Delete PVC
kubectl delete pvc mysql-pvc -n prod

# Delete namespace
kubectl delete namespace prod
```

## Health Checks

### Manual Health Check

```bash
# Check MySQL
kubectl exec -it <mysql-pod> -n prod -- mysqladmin ping -u root -pTest@123

# Check BankApp
kubectl exec -it <bankapp-pod> -n prod -- wget -O- http://localhost:8080/actuator/health
```

### Automated Health Check Script

```bash
#!/bin/bash
NAMESPACE=${1:-prod}

echo "Checking MySQL..."
kubectl get pods -l app=mysql -n $NAMESPACE

echo "Checking BankApp..."
kubectl get pods -l app=bankapp -n $NAMESPACE

echo "Checking Services..."
kubectl get svc -n $NAMESPACE

echo "Checking PVC..."
kubectl get pvc -n $NAMESPACE

echo "Recent Events..."
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -10
```

## Performance Tuning

### Scale BankApp

```bash
# Scale up
kubectl scale deployment bankapp --replicas=5 -n prod

# Or update values-prod.yaml and upgrade
# bankapp.replicas: 5
helm upgrade bankapp . -f values-prod.yaml -n prod
```

### Increase Resources

Update `values-prod.yaml`:

```yaml
bankapp:
  resources:
    requests:
      memory: "2Gi"
      cpu: "2"
    limits:
      memory: "4Gi"
      cpu: "4"
```

Then upgrade:
```bash
helm upgrade bankapp . -f values-prod.yaml -n prod
```

## Backup and Recovery

### Backup MySQL Data

```bash
# Create backup
kubectl exec -it <mysql-pod> -n prod -- \
  mysqldump -u root -pTest@123 bankappdb > backup.sql

# Or create snapshot of EBS volume via AWS Console/CLI
aws ec2 create-snapshot --volume-id <volume-id> --description "MySQL backup"
```

### Restore MySQL Data

```bash
# Copy backup to pod
kubectl cp backup.sql <mysql-pod>:/tmp/backup.sql -n prod

# Restore
kubectl exec -it <mysql-pod> -n prod -- \
  mysql -u root -pTest@123 bankappdb < /tmp/backup.sql
```

## Best Practices

1. **Always test in dev before prod**
2. **Use proper secret management in production**
3. **Monitor resource usage and adjust limits**
4. **Implement proper backup strategy**
5. **Use version control for values files**
6. **Document any custom configurations**
7. **Implement proper logging and monitoring**
8. **Regular security updates for images**

## Support and Debugging

For additional help:

```bash
# Get all resources
kubectl get all -n prod

# Get detailed information
kubectl describe all -n prod

# Export current configuration
helm get values bankapp -n prod > current-values.yaml
helm get manifest bankapp -n prod > current-manifest.yaml
```
