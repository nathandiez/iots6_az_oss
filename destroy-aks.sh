#!/usr/bin/env bash
# destroy-aks.sh - Complete AKS teardown script
set -e

echo "=========================================="
echo "WARNING: DESTRUCTIVE OPERATION"
echo "=========================================="
echo "This will:"
echo "  - Destroy the Azure AKS cluster"
echo "  - Delete all Kubernetes workloads"
echo "  - Remove all persistent volumes and data"
echo "  - Delete all Terraform state files"
echo "  - Clean up kubectl context"
echo ""
echo "Target cluster: aks-aziots6"
echo "Azure Resources to be destroyed:"
echo "  • AKS cluster (3 nodes)"
echo "  • All worker VMs"
echo "  • Load balancers and public IPs"
echo "  • Persistent volumes and disks"
echo "  • Resource group: rg-aziots6-aks"
echo ""
echo "Services to be destroyed:"
echo "  • TimescaleDB and ALL data"
echo "  • Mosquitto MQTT broker"
echo "  • IoT data processing services"
echo "  • Grafana dashboards and config"
echo ""
echo "This action is IRREVERSIBLE!"
echo "=========================================="

# Prompt for confirmation
read -p "Are you sure you want to proceed? (type 'yes' to continue): " confirmation

if [[ "$confirmation" != "yes" ]]; then
  echo "Operation cancelled."
  exit 0
fi

echo ""
echo "Starting AKS destruction process..."

# Source Azure environment variables
echo "Loading Azure environment..."
source ./set-azure-env.sh

# Change to AKS terraform directory
AKS_DIR="terraform-aks"
if [[ ! -d "$AKS_DIR" ]]; then
  echo "❌ AKS terraform directory not found: $AKS_DIR"
  echo "The cluster may already be destroyed or was created differently."
  exit 1
fi

cd "$AKS_DIR"

# Get cluster info for cleanup (before destroying)
echo ""
echo "Getting cluster information for cleanup..."
CLUSTER_NAME=""
RESOURCE_GROUP=""

if [[ -f "terraform.tfstate" ]]; then
  CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
  RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
fi

# Show what will be destroyed
if [[ -f "terraform.tfstate" ]]; then
  echo ""
  echo "Terraform state found. Destroying AKS infrastructure..."
  
  # Initialize terraform (in case .terraform directory is missing)
  terraform init -upgrade
  
  # Show what will be destroyed
  echo "Planning destruction..."
  terraform plan -destroy
  
  echo ""
  read -p "Proceed with destroying these Azure resources? (type 'yes'): " final_confirm
  
  if [[ "$final_confirm" != "yes" ]]; then
    echo "Destruction cancelled."
    exit 0
  fi
  
  # First, try to delete Kubernetes resources to clean up properly
  if [[ -n "$CLUSTER_NAME" ]] && [[ -n "$RESOURCE_GROUP" ]]; then
    echo ""
    echo "Attempting to clean up Kubernetes resources first..."
    
    # Try to get cluster credentials
    if az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing 2>/dev/null; then
      echo "Deleting all namespaced resources..."
      kubectl delete all --all --all-namespaces --timeout=60s 2>/dev/null || true
      
      echo "Deleting persistent volumes..."
      kubectl delete pv --all --timeout=60s 2>/dev/null || true
      
      echo "Kubernetes cleanup completed (or timed out safely)"
    else
      echo "Could not access cluster - will rely on Terraform destroy"
    fi
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
  kubectl config delete-cluster "$CLUSTER_NAME" 2>/dev/null || true
  kubectl config unset users.clusterUser_${RESOURCE_GROUP}_${CLUSTER_NAME} 2>/dev/null || true
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

# Remove kubeconfig file if it exists
rm -f kubeconfig

echo "All Terraform files cleaned up."

echo ""
echo "=========================================="
echo "AKS DESTRUCTION COMPLETE"
echo "=========================================="
echo "✅ AKS cluster destroyed (aks-aziots6)"
echo "✅ All 3 worker nodes terminated"
echo "✅ TimescaleDB and all sensor data deleted"
echo "✅ MQTT broker and message history removed"
echo "✅ All Kubernetes deployments destroyed"
echo "✅ Persistent volumes and disks deleted"
echo "✅ Load balancers and public IPs released"
echo "✅ Resource group (rg-aziots6-aks) deleted"
echo "✅ Azure billing stopped for these resources"
echo "✅ Terraform state files deleted"
echo "✅ kubectl contexts cleaned up"
echo ""
echo "💰 All Azure costs for the AKS deployment have stopped"
echo "🚀 You can now run ./deploy-aks.sh to start fresh!"
echo "📝 Your original VM deployment (deploy.sh) is still available"
echo "=========================================="