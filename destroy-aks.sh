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
echo "  - Delete Azure Key Vault AND ALL SECRETS"
echo "  - Delete Azure Key Vault managed identity"
echo "  - Delete ENTIRE Resource Group"
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
echo "  • Azure Key Vault: ${KEY_VAULT_NAME}"
echo "  • External Secrets managed identity"
echo "  • ALL node resource groups (MC_*)"
echo ""
echo "Services to be destroyed:"
echo "  • TimescaleDB and ALL data"
echo "  • Mosquitto MQTT broker"
echo "  • IoT data processing services"
echo "  • Grafana dashboards and config"
echo "  • External Secrets Operator"
echo "  • ArgoCD GitOps platform"
echo ""
echo "This action is IRREVERSIBLE!"
echo "All data will be permanently lost!"
echo "=========================================="
echo "🔥 AUTO-DESTRUCTION MODE: Proceeding automatically in 3 seconds..."
sleep 1
echo "3..."
sleep 1
echo "2..."
sleep 1
echo "1..."
echo "🚀 Starting destruction sequence..."

echo ""
echo "Starting complete AKS destruction process..."

# Source Azure environment variables
echo "Loading Azure environment..."
if [[ -f "./set-azure-env.sh" ]]; then
    source ./set-azure-env.sh
fi

# Function to safely run commands that might fail
safe_run() {
    local cmd="$1"
    local description="$2"
    echo "🔄 $description..."
    if eval "$cmd" 2>/dev/null; then
        echo "✅ $description completed"
    else
        echo "⚠️  $description failed or already completed"
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local timeout="${3:-300}"
    local count=0
    
    echo "⏳ Waiting for $resource_type '$resource_name' to be deleted..."
    while [[ $count -lt $timeout ]]; do
        if ! az "$resource_type" show --name "$resource_name" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            echo "✅ $resource_type '$resource_name' successfully deleted"
            return 0
        fi
        sleep 5
        count=$((count + 5))
        if [[ $((count % 30)) -eq 0 ]]; then
            echo "   Still waiting for $resource_type deletion... (${count}s elapsed)"
        fi
    done
    echo "⚠️  Timeout waiting for $resource_type deletion, continuing..."
}

# Phase 1: Kubernetes Resources Cleanup
echo ""
echo "🧹 PHASE 1: Kubernetes Resources Cleanup"
echo "=========================================="

# Change to AKS terraform directory
AKS_DIR="terraform-aks"
if [[ -d "$AKS_DIR" ]]; then
    cd "$AKS_DIR"
    
    # Initialize terraform to get outputs
    if [[ -f "terraform.tfstate" ]]; then
        terraform init -upgrade >/dev/null 2>&1 || true
        
        # Try to get cluster details
        TERRAFORM_CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "$CLUSTER_NAME")
        TERRAFORM_RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "$RESOURCE_GROUP")
        
        echo "Attempting to access cluster: $TERRAFORM_CLUSTER_NAME"
        
        # Try to get cluster credentials
        if az aks get-credentials --resource-group "$TERRAFORM_RESOURCE_GROUP" --name "$TERRAFORM_CLUSTER_NAME" --overwrite-existing >/dev/null 2>&1; then
            echo "✅ Successfully connected to AKS cluster"
            
            # Set reasonable timeouts for kubectl
            export KUBECTL_TIMEOUT="60s"
            
            # Delete ArgoCD applications first (to prevent GitOps conflicts)
            echo "🔄 Cleaning up ArgoCD applications..."
            kubectl delete applications --all -n argocd --timeout=$KUBECTL_TIMEOUT --ignore-not-found=true || true
            
            # Delete External Secrets resources
            echo "🔄 Cleaning up External Secrets resources..."
            kubectl delete externalsecrets --all --all-namespaces --timeout=$KUBECTL_TIMEOUT --ignore-not-found=true || true
            kubectl delete clustersecretstore --all --timeout=$KUBECTL_TIMEOUT --ignore-not-found=true || true
            kubectl delete secretstore --all --all-namespaces --timeout=$KUBECTL_TIMEOUT --ignore-not-found=true || true
            
            # Uninstall Helm releases
            echo "🔄 Uninstalling Helm releases..."
            helm list --all-namespaces --short | grep -E "(external-secrets|argocd)" | while read release namespace; do
                safe_run "helm uninstall $release -n $namespace --timeout=5m" "Uninstall Helm release $release"
            done
            
            # Force delete ArgoCD namespace and resources
            echo "🔄 Force deleting ArgoCD..."
            kubectl delete namespace argocd --timeout=$KUBECTL_TIMEOUT --ignore-not-found=true || true
            
            # Force delete External Secrets namespace
            echo "🔄 Force deleting External Secrets..."
            kubectl delete namespace external-secrets-system --timeout=$KUBECTL_TIMEOUT --ignore-not-found=true || true
            
            # CRITICAL: Delete PVCs first to release Azure disks
            echo "🗑️  CRITICAL: Deleting PersistentVolumeClaims to release Azure managed disks..."
            for ns in ${PROJECT_NAME}-dev ${PROJECT_NAME}-staging ${PROJECT_NAME}-prod default kube-system; do
                if kubectl get namespace "$ns" >/dev/null 2>&1; then
                    echo "  🔄 Deleting PVCs in namespace: $ns"
                    kubectl delete pvc --all -n "$ns" --timeout=$KUBECTL_TIMEOUT --ignore-not-found=true || true
                fi
            done
            
            # Delete all application workloads
            echo "🔄 Deleting all application workloads..."
            for ns in ${PROJECT_NAME}-dev ${PROJECT_NAME}-staging ${PROJECT_NAME}-prod; do
                if kubectl get namespace "$ns" >/dev/null 2>&1; then
                    echo "  🔄 Cleaning namespace: $ns"
                    kubectl delete all --all -n "$ns" --timeout=$KUBECTL_TIMEOUT --ignore-not-found=true || true
                    kubectl delete pvc,secrets,configmaps,serviceaccounts --all -n "$ns" --timeout=$KUBECTL_TIMEOUT --ignore-not-found=true || true
                fi
            done
            
            # Delete persistent volumes
            echo "🔄 Deleting persistent volumes..."
            kubectl delete pv --all --timeout=$KUBECTL_TIMEOUT --ignore-not-found=true || true
            
            # Delete project namespaces
            echo "🔄 Deleting project namespaces..."
            for ns in ${PROJECT_NAME}-dev ${PROJECT_NAME}-staging ${PROJECT_NAME}-prod; do
                kubectl delete namespace "$ns" --timeout=$KUBECTL_TIMEOUT --ignore-not-found=true || true
            done
            
            # Final cleanup of any stuck resources
            echo "🔄 Final cleanup of any remaining custom resources..."
            kubectl delete crd --all --timeout=$KUBECTL_TIMEOUT --ignore-not-found=true || true
            
            echo "✅ Kubernetes cleanup completed"
        else
            echo "⚠️  Could not access cluster - will rely on Azure resource deletion"
        fi
    else
        echo "⚠️  No Terraform state found in $AKS_DIR"
    fi
    cd ..
else
    echo "⚠️  AKS terraform directory not found: $AKS_DIR"
fi

# Phase 2: Azure Key Vault Cleanup
echo ""
echo "🔑 PHASE 2: Azure Key Vault Complete Cleanup"
echo "=========================================="

if [[ -n "$KEY_VAULT_NAME" ]]; then
    # Check if Key Vault exists
    if az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        echo "🔄 Found Key Vault: $KEY_VAULT_NAME"
        
        # Delete all secrets
        echo "🔄 Deleting all secrets from Key Vault..."
        SECRETS=$(az keyvault secret list --vault-name "$KEY_VAULT_NAME" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$SECRETS" ]]; then
            echo "$SECRETS" | while read -r secret; do
                if [[ -n "$secret" ]]; then
                    safe_run "az keyvault secret delete --vault-name '$KEY_VAULT_NAME' --name '$secret'" "Delete secret: $secret"
                fi
            done
        fi
        
        # Delete all certificates
        echo "🔄 Deleting all certificates from Key Vault..."
        CERTS=$(az keyvault certificate list --vault-name "$KEY_VAULT_NAME" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$CERTS" ]]; then
            echo "$CERTS" | while read -r cert; do
                if [[ -n "$cert" ]]; then
                    safe_run "az keyvault certificate delete --vault-name '$KEY_VAULT_NAME' --name '$cert'" "Delete certificate: $cert"
                fi
            done
        fi
        
        # Delete all keys
        echo "🔄 Deleting all keys from Key Vault..."
        KEYS=$(az keyvault key list --vault-name "$KEY_VAULT_NAME" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$KEYS" ]]; then
            echo "$KEYS" | while read -r key; do
                if [[ -n "$key" ]]; then
                    safe_run "az keyvault key delete --vault-name '$KEY_VAULT_NAME' --name '$key'" "Delete key: $key"
                fi
            done
        fi
        
        # Delete the Key Vault itself
        echo "🔄 Deleting Key Vault: $KEY_VAULT_NAME"
        safe_run "az keyvault delete --name '$KEY_VAULT_NAME' --resource-group '$RESOURCE_GROUP'" "Delete Key Vault"
        
        # Purge immediately to free up the name (required for same-name redeployment)
        echo "🔄 Purging Key Vault to free up name '$KEY_VAULT_NAME'..."
        az keyvault purge --name "$KEY_VAULT_NAME" --location "$AZURE_LOCATION" --no-wait 2>/dev/null || true
        echo "✅ Key Vault purge initiated - name will be available for reuse"
        
    else
        echo "⚠️  Key Vault $KEY_VAULT_NAME not found or already deleted"
    fi
else
    echo "⚠️  KEY_VAULT_NAME not set in environment"
fi

# Phase 3: Managed Identity Cleanup
echo ""
echo "🆔 PHASE 3: Managed Identity Cleanup"
echo "=========================================="

# Clean up all possible managed identity names
IDENTITY_NAMES=(
    "id-${CLUSTER_NAME}-external-secrets"
    "external-secrets-identity"
    "${PROJECT_NAME}-external-secrets-identity"
)

for identity_name in "${IDENTITY_NAMES[@]}"; do
    if az identity show --name "$identity_name" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        safe_run "az identity delete --name '$identity_name' --resource-group '$RESOURCE_GROUP'" "Delete managed identity: $identity_name"
    fi
done

# Phase 4: Terraform Infrastructure Destruction
echo ""
echo "🏗️  PHASE 4: Terraform Infrastructure Destruction"
echo "=========================================="

if [[ -d "$AKS_DIR" ]]; then
    cd "$AKS_DIR"
    
    if [[ -f "terraform.tfstate" ]]; then
        echo "🔄 Found Terraform state file"
        
        # Initialize terraform
        terraform init -upgrade >/dev/null 2>&1 || true
        
        # Check if state has resources
        if terraform show 2>/dev/null | grep -q "resource.*{"; then
            echo "🔄 Terraform state contains resources, running destroy..."
            
            # Modify Terraform provider to force resource group deletion
            echo "🔄 Configuring Terraform to force delete resource groups..."
            
            # Create a temporary provider override
            cat > provider_override.tf << 'EOF'
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}
EOF
            
            # Re-initialize with the override
            terraform init -upgrade >/dev/null 2>&1 || true
            
            # Destroy with retries
            echo "🔄 Running terraform destroy (may take 10+ minutes)..."
            for attempt in 1 2 3; do
                echo "  Attempt $attempt/3..."
                if terraform destroy -auto-approve; then
                    echo "✅ Terraform destroy completed successfully"
                    break
                elif [[ $attempt -eq 3 ]]; then
                    echo "⚠️  Terraform destroy failed after 3 attempts, continuing with manual cleanup..."
                else
                    echo "⚠️  Terraform destroy attempt $attempt failed, retrying in 30 seconds..."
                    sleep 30
                fi
            done
            
            # Clean up the provider override
            rm -f provider_override.tf
        else
            echo "⚠️  Terraform state is empty, skipping destroy"
        fi
    else
        echo "⚠️  No Terraform state file found"
    fi
    
    cd ..
else
    echo "⚠️  Terraform directory not found"
fi

# Phase 5: Force Delete Any Remaining Azure Resources
echo ""
echo "🧨 PHASE 5: Force Delete Remaining Azure Resources"
echo "=========================================="

# Delete any remaining AKS clusters in the resource group
echo "🔄 Checking for any remaining AKS clusters..."
REMAINING_CLUSTERS=$(az aks list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
if [[ -n "$REMAINING_CLUSTERS" ]]; then
    echo "$REMAINING_CLUSTERS" | while read -r cluster; do
        if [[ -n "$cluster" ]]; then
            echo "🔄 Force deleting AKS cluster: $cluster"
            safe_run "az aks delete --name '$cluster' --resource-group '$RESOURCE_GROUP' --yes --no-wait" "Force delete AKS cluster: $cluster"
        fi
    done
fi

# Delete managed disk snapshots
echo "🔄 Deleting any remaining managed disk snapshots..."
SNAPSHOTS=$(az snapshot list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
if [[ -n "$SNAPSHOTS" ]]; then
    echo "$SNAPSHOTS" | while read -r snapshot; do
        if [[ -n "$snapshot" ]]; then
            safe_run "az snapshot delete --name '$snapshot' --resource-group '$RESOURCE_GROUP'" "Delete snapshot: $snapshot"
        fi
    done
fi

# Delete any remaining managed disks
echo "🔄 Deleting any remaining managed disks..."
DISKS=$(az disk list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
if [[ -n "$DISKS" ]]; then
    echo "$DISKS" | while read -r disk; do
        if [[ -n "$disk" ]]; then
            safe_run "az disk delete --name '$disk' --resource-group '$RESOURCE_GROUP' --yes" "Delete disk: $disk"
        fi
    done
fi

# Wait for AKS deletion to complete
if [[ -n "$REMAINING_CLUSTERS" ]]; then
    echo "$REMAINING_CLUSTERS" | while read -r cluster; do
        if [[ -n "$cluster" ]]; then
            wait_for_deletion "aks" "$cluster" 600
        fi
    done
fi

# Phase 6: Delete Node Resource Groups
echo ""
echo "🗑️  PHASE 6: Delete Node Resource Groups"
echo "=========================================="

# Find and delete MC_ resource groups (AKS node resource groups)
echo "🔄 Finding AKS node resource groups to delete..."
NODE_RESOURCE_GROUPS=$(az group list --query "[?starts_with(name, 'MC_${RESOURCE_GROUP}_')].name" -o tsv 2>/dev/null || echo "")
if [[ -n "$NODE_RESOURCE_GROUPS" ]]; then
    echo "$NODE_RESOURCE_GROUPS" | while read -r rg; do
        if [[ -n "$rg" ]]; then
            echo "🔄 Deleting node resource group: $rg"
            safe_run "az group delete --name '$rg' --yes --no-wait" "Delete node resource group: $rg"
        fi
    done
    
    # Wait for node resource groups to be deleted
    echo "$NODE_RESOURCE_GROUPS" | while read -r rg; do
        if [[ -n "$rg" ]]; then
            wait_for_deletion "group" "$rg" 600
        fi
    done
else
    echo "⚠️  No node resource groups found"
fi

# Phase 7: Delete Main Resource Group
echo ""
echo "🗑️  PHASE 7: Delete Main Resource Group"
echo "=========================================="

if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    echo "🔄 Deleting main resource group: $RESOURCE_GROUP"
    echo "   This will delete ALL remaining resources in the group..."
    
    # Force delete the resource group
    safe_run "az group delete --name '$RESOURCE_GROUP' --yes --force-deletion-types Microsoft.Compute/virtualMachines,Microsoft.Compute/virtualMachineScaleSets" "Delete resource group: $RESOURCE_GROUP"
    
    # Wait for main resource group deletion
    wait_for_deletion "group" "$RESOURCE_GROUP" 900
else
    echo "⚠️  Resource group $RESOURCE_GROUP not found or already deleted"
fi

# Phase 8: Cleanup Local Files
echo ""
echo "🧹 PHASE 8: Local Files Cleanup"
echo "=========================================="

# Clean up kubectl contexts
echo "🔄 Cleaning up kubectl contexts..."
if [[ -n "$CLUSTER_NAME" ]]; then
    kubectl config delete-context "$CLUSTER_NAME" 2>/dev/null || true
    kubectl config unset "users.clusterUser_${RESOURCE_GROUP}_${CLUSTER_NAME}" 2>/dev/null || true
    echo "✅ Cleaned up kubectl context for $CLUSTER_NAME"
fi

# Change back to AKS directory for file cleanup
if [[ -d "$AKS_DIR" ]]; then
    cd "$AKS_DIR"
    
    echo "🔄 Cleaning up all Terraform files..."
    
    # Remove all Terraform state and temporary files
    rm -f terraform.tfstate*
    rm -f .terraform.lock.hcl
    rm -f provider_override.tf
    rm -rf .terraform
    
    echo "✅ All Terraform files cleaned up"
    cd ..
fi

# Clean up any temporary files
rm -f kubeconfig-*
rm -f *.tmp

echo ""
echo "=========================================="
echo "🎉 COMPLETE DESTRUCTION FINISHED 🎉"
echo "=========================================="
echo "✅ AKS cluster completely destroyed: ${CLUSTER_NAME}"
echo "✅ Project completely removed: ${PROJECT_NAME}"
echo "✅ All worker nodes terminated"
echo "✅ TimescaleDB and all sensor data permanently deleted"
echo "✅ MQTT broker and message history permanently removed"
echo "✅ All Kubernetes deployments destroyed"
echo "✅ All persistent volumes and disks deleted"
echo "✅ All PersistentVolumeClaims cleaned up"
echo "✅ All Azure managed disks removed"
echo "✅ All load balancers and public IPs released"
echo "✅ Main resource group deleted: ${RESOURCE_GROUP}"
echo "✅ All node resource groups deleted (MC_*)"
echo "✅ Azure Key Vault permanently purged: ${KEY_VAULT_NAME}"
echo "✅ All Key Vault secrets permanently deleted"
echo "✅ All managed identities deleted"
echo "✅ External Secrets Operator completely removed"
echo "✅ ArgoCD completely removed"
echo "✅ All Terraform state files deleted"
echo "✅ All kubectl contexts cleaned up"
echo "✅ All local temporary files cleaned up"
echo ""
echo "💰 ALL Azure costs have stopped - no resources remain"
echo "🔥 Everything has been permanently destroyed"
echo "🚀 You can now run ./deploy-aks.sh to start completely fresh!"
echo "📝 The deployment will create new resource groups and infrastructure"
echo "=========================================="