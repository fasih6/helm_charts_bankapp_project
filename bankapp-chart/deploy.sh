#!/bin/bash

# BankApp Helm Chart Deployment Script
# Usage: ./deploy.sh [environment] [action]
# Example: ./deploy.sh dev install
#          ./deploy.sh prod upgrade

set -e

# Configuration
CHART_NAME="bankapp"
CHART_PATH="."
RELEASE_NAME="bankapp"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_usage() {
    echo "Usage: $0 [environment] [action]"
    echo ""
    echo "Environments:"
    echo "  dev     - Development environment"
    echo "  prod    - Production environment"
    echo "  default - Default values (no environment specific overrides)"
    echo ""
    echo "Actions:"
    echo "  install   - Install the chart"
    echo "  upgrade   - Upgrade the chart"
    echo "  uninstall - Uninstall the chart"
    echo "  status    - Show release status"
    echo "  test      - Test the chart (dry-run)"
    echo ""
    echo "Example: $0 dev install"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        print_error "Helm is not installed. Please install Helm 3.x"
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install kubectl"
        exit 1
    fi
    
    # Check kubectl connectivity
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster. Check your kubeconfig"
        exit 1
    fi
    
    print_info "Prerequisites check passed"
}

validate_chart() {
    print_info "Validating Helm chart..."
    if helm lint $CHART_PATH; then
        print_info "Chart validation passed"
    else
        print_error "Chart validation failed"
        exit 1
    fi
}

# Main script
if [ $# -lt 2 ]; then
    print_error "Invalid number of arguments"
    print_usage
    exit 1
fi

ENVIRONMENT=$1
ACTION=$2

# Set values file based on environment
case $ENVIRONMENT in
    dev)
        VALUES_FILE="values-dev.yaml"
        NAMESPACE="dev"
        ;;
    prod)
        VALUES_FILE="values-prod.yaml"
        NAMESPACE="prod"
        ;;
    default)
        VALUES_FILE="values.yaml"
        NAMESPACE="default"
        ;;
    *)
        print_error "Invalid environment: $ENVIRONMENT"
        print_usage
        exit 1
        ;;
esac

print_info "Environment: $ENVIRONMENT"
print_info "Action: $ACTION"
print_info "Values file: $VALUES_FILE"
print_info "Namespace: $NAMESPACE"

check_prerequisites

# Ensure namespace exists
kubectl get namespace $NAMESPACE &> /dev/null || kubectl create namespace $NAMESPACE

case $ACTION in
    test)
        print_info "Testing chart with dry-run..."
        validate_chart
        helm install $RELEASE_NAME $CHART_PATH \
            -f $VALUES_FILE \
            --namespace $NAMESPACE \
            --dry-run --debug
        print_info "Dry-run completed successfully"
        ;;
    
    install)
        validate_chart
        print_info "Installing chart..."
        helm install $RELEASE_NAME $CHART_PATH \
            -f $VALUES_FILE \
            --namespace $NAMESPACE \
            --create-namespace
        
        print_info "Installation completed!"
        echo ""
        print_info "Run the following to check status:"
        echo "  helm status $RELEASE_NAME --namespace $NAMESPACE"
        echo "  kubectl get all --namespace $NAMESPACE"
        ;;
    
    upgrade)
        validate_chart
        print_info "Upgrading chart..."
        helm upgrade $RELEASE_NAME $CHART_PATH \
            -f $VALUES_FILE \
            --namespace $NAMESPACE
        
        print_info "Upgrade completed!"
        echo ""
        print_info "Run the following to check status:"
        echo "  helm status $RELEASE_NAME --namespace $NAMESPACE"
        echo "  kubectl get all --namespace $NAMESPACE"
        ;;
    
    uninstall)
        print_warning "This will uninstall the release: $RELEASE_NAME"
        read -p "Are you sure? (yes/no): " -r
        echo
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "Uninstalling chart..."
            helm uninstall $RELEASE_NAME --namespace $NAMESPACE
            print_info "Uninstall completed!"
            print_warning "PVCs are not deleted automatically. To delete them, run:"
            echo "  kubectl delete pvc --namespace $NAMESPACE mysql-pvc"
        else
            print_info "Uninstall cancelled"
        fi
        ;;
    
    status)
        print_info "Getting release status..."
        helm status $RELEASE_NAME --namespace $NAMESPACE
        echo ""
        kubectl get all --namespace $NAMESPACE
        ;;
    
    *)
        print_error "Invalid action: $ACTION"
        print_usage
        exit 1
        ;;
esac

exit 0
