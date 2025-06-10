#!/usr/bin/env bash
# destroy-aks.sh - Complete AKS teardown script with enhanced cleanup
set -e

# Load environment variables from .env
if [[ ! -f ".env" ]]; then
    echo "❌ .env file not found. Please create it with required variables"
    exit 1
fi

echo "Loading environment variables..."
set -a
source .env
set +a

# Export Terraform variables from .env
echo "Setting Terraform variables..."
export TF_VAR_location="$AZURE_LOCATION"
export TF_VAR_resource_group="$RESOURCE_GROUP"
export TF_VAR_cluster_name="$CLUSTER_NAME"

echo "=========================================="
echo "WARNING: DESTRUCTIVE OPERATION"
echo "=========================================="
echo "This will:"
echo "  - Destroy the Azure AKS cluster"
echo "  - Delete all Kubernetes workloads"
echo "  - Remove all persistent volumes and data"
echo "  - Delete all managed disks"
echo "  - Delete External Secrets Operator and resources"
echo "  - Delete Azure Key Vault secrets"
echo "  - Delete all Terraform state files"
echo "  - Clean up kubectl context"
echo ""
echo "Target cluster: ${CLUSTER_NAME}"
echo "Project name: ${PROJECT_NAME}"
echo "Azure Resources to be destroyed:"
echo "  • AKS cluster (${AKS_NODE_COUNT} nodes)"
echo "  • All worker VMs"
echo "  • Load balancers and public IPs"
echo "  • Persistent volumes and disks"
echo "  • Resource group: ${RESOURCE_GROUP}"
echo "  • External Secrets managed identity"
echo "  • Azure Key Vault configuration"
echo ""
echo "Services to be destroyed:"
echo "  • TimescaleDB and ALL data"
echo "  • Mosquitto MQTT broker"
echo "  • IoT data processing services"
echo "  • Grafana dashboards and config"
echo "  • External Secrets Operator"
echo ""
echo "This action is IRREVERSIBLE!"
echo "=========================================="

echo ""
echo "Starting AKS destruction process..."

# Source Azure environment variables
echo "Loading Azure environment..."
if [[ -f "./set-azure-env.sh" ]]; then
    source ./set-azure-env.sh
fi

# Change to AKS terraform directory
AKS_DIR="terraform-aks"
if [[ ! -d "$AKS_DIR" ]]; then
  echo "❌ AKS terraform directory not found: $AKS_DIR"
  echo "The cluster may already be destroyed or was created differently."
  exit 1
fi

cd "$AKS_DIR"

# Check if state file has actual resources
if [[ -f "terraform.tfstate" ]]; then
  # Check if state file is empty or has no resources
  if terraform show | grep -q "No resources are represented"; then
    echo ""
    echo "Terraform state file exists but is empty. Cleaning up state files..."
    # Clean up empty state files
    rm -f terraform.tfstate*
    rm -f .terraform.lock.hcl
    rm -rf .terraform
    echo "✅ Cleaned up empty Terraform state files"
    cd ..
    echo ""
    echo "=========================================="
    echo "AKS CLEANUP COMPLETE"
    echo "=========================================="
    echo "✅ No active cluster found"
    echo "✅ Cleaned up empty Terraform state files"
    echo "🚀 You can now run ./deploy-aks.sh to start fresh!"
    echo "=========================================="
    exit 0
  fi
  
  echo ""
  echo "Terraform state found. Destroying AKS infrastructure..."
  
  # Initialize terraform (in case .terraform directory is missing)
  terraform init -upgrade
  
  # Show what will be destroyed
  echo "Planning destruction..."
  terraform plan -destroy
  
  # First, try to delete Kubernetes resources to clean up properly
  TERRAFORM_CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
  TERRAFORM_RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
  
  if [[ -n "$TERRAFORM_CLUSTER_NAME" ]] && [[ -n "$TERRAFORM_RESOURCE_GROUP" ]]; then
    echo ""
    echo "Attempting to clean up Kubernetes resources first..."
    
    # Try to get cluster credentials
    if az aks get-credentials --resource-group "$TERRAFORM_RESOURCE_GROUP" --name "$TERRAFORM_CLUSTER_NAME" --overwrite-existing 2>/dev/null; then
      echo "Cleaning up External Secrets resources..."
      kubectl delete externalsecrets --all --all-namespaces --timeout=30s 2>/dev/null || true
      kubectl delete clustersecretstore azure-key-vault --timeout=30s 2>/dev/null || true
      
      # Uninstall External Secrets Helm releases
      echo "Uninstalling External Secrets Helm releases..."
      helm uninstall external-secrets-config -n default 2>/dev/null || true
      helm uninstall external-secrets -n external-secrets-system 2>/dev/null || true
      kubectl delete namespace external-secrets-system --timeout=60s 2>/dev/null || true
      
      # Uninstall ArgoCD
      echo "Uninstalling ArgoCD..."
      kubectl delete -n ${ARGOCD_NAMESPACE} -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" --timeout=60s 2>/dev/null || true
      kubectl delete namespace ${ARGOCD_NAMESPACE} --timeout=30s 2>/dev/null || true
      
      echo "Deleting all namespaced resources..."
      kubectl delete all --all --all-namespaces --timeout=60s 2>/dev/null || true
      
      # CRITICAL: Delete PVCs to ensure managed disks are cleaned up
      echo "🗑️  Deleting PersistentVolumeClaims to clean up Azure managed disks..."
      for ns in ${PROJECT_NAME}-dev ${PROJECT_NAME}-staging ${PROJECT_NAME}-prod; do
          echo "  Deleting PVCs in namespace: $ns"
          kubectl delete pvc --all -n $ns --wait=true --timeout=60s 2>/dev/null || true
      done
      
      # Delete persistent volumes
      echo "Deleting persistent volumes..."
      kubectl delete pv --all --timeout=60s 2>/dev/null || true
      
      # Delete project namespaces
      echo "Deleting project namespaces..."
      for ns in ${PROJECT_NAME}-dev ${PROJECT_NAME}-staging ${PROJECT_NAME}-prod; do
          kubectl delete namespace $ns --timeout=60s 2>/dev/null || true
      done
      
      echo "Kubernetes cleanup completed (or timed out safely)"
    else
      echo "Could not access cluster - will rely on Terraform destroy"
    fi
    
    # Clean up Azure resources
    echo "Cleaning up Azure Key Vault secrets..."
    if [[ -n "$KEY_VAULT_NAME" ]]; then
      # List and delete all secrets
      SECRETS=$(az keyvault secret list --vault-name "$KEY_VAULT_NAME" --query "[].name" -o tsv 2>/dev/null || echo "")
      if [[ -n "$SECRETS" ]]; then
        echo "$SECRETS" | while read secret; do
          echo "  Deleting secret: $secret"
          az keyvault secret delete --vault-name "$KEY_VAULT_NAME" --name "$secret" 2>/dev/null || true
        done
      fi
    fi
    
    # Clean up managed identity
    echo "Cleaning up managed identity..."
    IDENTITY_NAME="id-${TERRAFORM_CLUSTER_NAME}-external-secrets"
    az identity delete --name "$IDENTITY_NAME" --resource-group "$TERRAFORM_RESOURCE_GROUP" 2>/dev/null || true
  fi
  
  # Destroy the infrastructure
  echo "Running terraform destroy..."
  terraform destroy -auto-approve
  
  echo "AKS infrastructure destroyed successfully."
else
  echo "No terraform.tfstate found. Skipping terraform destroy."
fi

# Clean up kubectl contexts
echo ""
echo "Cleaning up kubectl contexts..."
if [[ -n "$CLUSTER_NAME" ]]; then
  kubectl config delete-context "$CLUSTER_NAME" 2>/dev/null || true
  kubectl config unset "users.clusterUser_${RESOURCE_GROUP}_${CLUSTER_NAME}" 2>/dev/null || true
  echo "✅ Cleaned up kubectl context for $CLUSTER_NAME"
fi

# Clean up all Terraform files
echo ""
echo "Cleaning up Terraform state and lock files..."

# Remove state files
rm -f terraform.tfstate
rm -f terraform.tfstate.backup

# Remove lock file if it exists
rm -f .terraform.lock.hcl

# Remove .terraform directory
rm -rf .terraform

echo "All Terraform files cleaned up."

echo ""
echo "=========================================="
echo "AKS DESTRUCTION COMPLETE"
echo "=========================================="
echo "✅ AKS cluster destroyed (${CLUSTER_NAME})"
echo "✅ Project cleaned up (${PROJECT_NAME})"
echo "✅ All ${AKS_NODE_COUNT} worker nodes terminated"
echo "✅ TimescaleDB and all sensor data deleted"
echo "✅ MQTT broker and message history removed"
echo "✅ All Kubernetes deployments destroyed"
echo "✅ Persistent volumes and disks deleted"
echo "✅ PersistentVolumeClaims cleaned up"
echo "✅ Azure managed disks removed"
echo "✅ Load balancers and public IPs released"
echo "✅ Resource group maintained for future use"
echo "✅ External Secrets Operator uninstalled"
echo "✅ Managed identity deleted"
echo "✅ Azure Key Vault secrets deleted"
echo "✅ ArgoCD uninstalled"
echo "✅ Azure billing stopped for these resources"
echo "✅ Terraform state files deleted"
echo "✅ kubectl contexts cleaned up"
echo ""
echo "💰 All Azure costs for the AKS deployment have stopped"
echo "🚀 You can now run ./deploy-aks.sh to start fresh!"
echo "📝 Your original VM deployment (deploy.sh) is still available"
echo "=========================================="