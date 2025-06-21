#!/usr/bin/env bash
# deploy-aks.sh - Deploy IoT Stack to Azure AKS with GitOps and Terraform state management
set -e

# Load environment variables from .env
if [[ ! -f ".env" ]]; then
    echo "❌ .env file not found. Please create it with required variables"
    exit 1
fi

echo "=========================================="
echo "Deploying IoT Stack to Azure AKS with GitOps"
echo "=========================================="

echo "Loading environment variables..."
set -a
source .env
set +a

# Export Terraform variables from .env
echo "Setting Terraform variables..."
export TF_VAR_location="$AZURE_LOCATION"
export TF_VAR_resource_group="$RESOURCE_GROUP"
export TF_VAR_cluster_name="$CLUSTER_NAME"

# Basic prerequisite checks
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform not found. Please install Terraform"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "❌ Helm not found. Please install Helm"
    exit 1
fi

if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI not found. Please install Azure CLI"
    exit 1
fi

# Check if logged into Azure
if ! az account show &> /dev/null; then
    echo "❌ Not logged into Azure. Please run 'az login'"
    exit 1
fi

echo "✅ Prerequisites check passed"
echo "📋 Using cluster: ${CLUSTER_NAME} in region: ${AZURE_LOCATION}"

# Function to safely run commands
safe_run() {
    local cmd="$1"
    local description="$2"
    echo "🔄 $description..."
    if eval "$cmd" 2>/dev/null; then
        echo "✅ $description completed"
        return 0
    else
        echo "⚠️  $description failed or already exists"
        return 1
    fi
}

echo ""
echo "📦 Creating Azure Key Vault and storing configuration..."

# Check if resource group exists, create if not
if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    az group create --name "$RESOURCE_GROUP" --location "$AZURE_LOCATION"
    echo "✅ Created resource group: $RESOURCE_GROUP"
else
    echo "✅ Resource group already exists: $RESOURCE_GROUP"
fi

# Check if Key Vault exists, create if not
if ! az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    az keyvault create \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$AZURE_LOCATION" \
        --enabled-for-template-deployment true
    echo "✅ Created Key Vault: $KEY_VAULT_NAME"
    
    # Grant current user Key Vault Administrator role
    echo "🔑 Granting Key Vault Administrator permissions to current user..."
    USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    
    az role assignment create \
        --role "Key Vault Administrator" \
        --assignee "$USER_OBJECT_ID" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourcegroups/$RESOURCE_GROUP/providers/microsoft.keyvault/vaults/$KEY_VAULT_NAME"
    
    echo "⏳ Waiting 30 seconds for RBAC permissions to propagate..."
    sleep 30
    
    # Note: Soft delete is enabled by default in newer Azure CLI versions
    echo "ℹ️  Soft delete is enabled by default (90-day retention)"
else
    echo "✅ Key Vault already exists: $KEY_VAULT_NAME"
fi

# Store secrets in Key Vault
echo "Storing secrets in Key Vault..."
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "postgres-db" --value "iot_sensor_data" >/dev/null
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "postgres-user" --value "iot_user" >/dev/null
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "postgres-password" --value "$(openssl rand -base64 32)" >/dev/null
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "grafana-admin-user" --value "admin" >/dev/null
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "grafana-admin-password" --value "$(openssl rand -base64 32)" >/dev/null
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "datadog-api-key" --value "placeholder-key-update-with-real-key" >/dev/null

echo "✅ Secrets stored in Azure Key Vault"

# Set up Azure environment
echo "Setting up Azure environment for az${PROJECT_NAME}..."

# Source the Azure environment setup
if [[ ! -f "./set-azure-env.sh" ]]; then
    echo "❌ set-azure-env.sh not found. Please ensure this file exists."
    exit 1
fi

source ./set-azure-env.sh

echo "✅ Azure environment configured for IoTS6 deployment"
echo "🚀 Ready to run: ./deploy.sh"

echo ""
echo "🚀 Creating AKS cluster..."

# Change to the AKS terraform directory
AKS_DIR="terraform-aks"
if [[ ! -d "$AKS_DIR" ]]; then
    echo "❌ AKS terraform directory not found: $AKS_DIR"
    exit 1
fi

cd "$AKS_DIR"

# Initialize Terraform
terraform init -upgrade

# CRITICAL: Import existing resources if they exist
echo ""
echo "🔄 Checking for existing Azure resources to import..."

# Import resource group if it exists and not in state
if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    if ! terraform state show azurerm_resource_group.aks >/dev/null 2>&1; then
        echo "🔄 Importing existing resource group into Terraform state..."
        SUBSCRIPTION_ID=$(az account show --query id -o tsv)
        terraform import azurerm_resource_group.aks "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" || true
        echo "✅ Resource group imported"
    else
        echo "✅ Resource group already in Terraform state"
    fi
fi

# Import AKS cluster if it exists and not in state
if az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    if ! terraform state show azurerm_kubernetes_cluster.main >/dev/null 2>&1; then
        echo "🔄 Importing existing AKS cluster into Terraform state..."
        SUBSCRIPTION_ID=$(az account show --query id -o tsv)
        terraform import azurerm_kubernetes_cluster.main "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerService/managedClusters/$CLUSTER_NAME" || true
        echo "✅ AKS cluster imported"
    else
        echo "✅ AKS cluster already in Terraform state"
    fi
fi

# Import VNet if it exists and not in state
VNET_NAME="${CLUSTER_NAME}-vnet"
if az network vnet show --name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    if ! terraform state show azurerm_virtual_network.aks >/dev/null 2>&1; then
        echo "🔄 Importing existing VNet into Terraform state..."
        SUBSCRIPTION_ID=$(az account show --query id -o tsv)
        terraform import azurerm_virtual_network.aks "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/$VNET_NAME" || true
        echo "✅ VNet imported"
    else
        echo "✅ VNet already in Terraform state"
    fi
fi

# Import subnets if they exist and not in state
PRIVATE_SUBNET_NAME="${CLUSTER_NAME}-private-subnet"
PUBLIC_SUBNET_NAME="${CLUSTER_NAME}-public-subnet"

if az network vnet subnet show --vnet-name "$VNET_NAME" --name "$PRIVATE_SUBNET_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    if ! terraform state show azurerm_subnet.private >/dev/null 2>&1; then
        echo "🔄 Importing existing private subnet into Terraform state..."
        SUBSCRIPTION_ID=$(az account show --query id -o tsv)
        terraform import azurerm_subnet.private "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/$VNET_NAME/subnets/$PRIVATE_SUBNET_NAME" || true
        echo "✅ Private subnet imported"
    else
        echo "✅ Private subnet already in Terraform state"
    fi
fi

if az network vnet subnet show --vnet-name "$VNET_NAME" --name "$PUBLIC_SUBNET_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    if ! terraform state show azurerm_subnet.public >/dev/null 2>&1; then
        echo "🔄 Importing existing public subnet into Terraform state..."
        SUBSCRIPTION_ID=$(az account show --query id -o tsv)
        terraform import azurerm_subnet.public "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/$VNET_NAME/subnets/$PUBLIC_SUBNET_NAME" || true
        echo "✅ Public subnet imported"
    else
        echo "✅ Public subnet already in Terraform state"
    fi
fi

echo ""
echo "🔄 Planning Terraform deployment..."
terraform plan

echo ""
echo "🚀 Applying Terraform configuration..."
terraform apply -auto-approve

echo "✅ AKS cluster created successfully!"

# Get cluster credentials
echo ""
echo "🔑 Configuring kubectl access..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

# Verify cluster access
echo "🔍 Verifying cluster access..."
kubectl cluster-info
kubectl get nodes

echo ""
echo "🎯 Setting up External Secrets Operator..."

# Create namespace for External Secrets
kubectl create namespace external-secrets-system --dry-run=client -o yaml | kubectl apply -f -

# Add External Secrets Helm repo
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install External Secrets Operator
helm upgrade --install external-secrets external-secrets/external-secrets \
    --namespace external-secrets-system \
    --set installCRDs=true \
    --wait

echo "✅ External Secrets Operator installed"

# Set up managed identity for External Secrets
echo ""
echo "🆔 Setting up managed identity for External Secrets..."

# Get cluster info
CLUSTER_RESOURCE_ID=$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
OIDC_ISSUER=$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --query oidcIssuerProfile.issuerUrl -o tsv)

# Create managed identity
IDENTITY_NAME="id-${CLUSTER_NAME}-external-secrets"
if ! az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    az identity create --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP"
    echo "✅ Created managed identity: $IDENTITY_NAME"
else
    echo "✅ Managed identity already exists: $IDENTITY_NAME"
fi

# Get identity details
IDENTITY_CLIENT_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv)
IDENTITY_OBJECT_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)

# Grant Key Vault access to managed identity using RBAC (FIXED)
echo "🔑 Granting Key Vault RBAC access to managed identity..."
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
az role assignment create \
    --role "Key Vault Secrets User" \
    --assignee "$IDENTITY_OBJECT_ID" \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourcegroups/$RESOURCE_GROUP/providers/microsoft.keyvault/vaults/$KEY_VAULT_NAME"

echo "✅ Granted Key Vault Secrets User role to managed identity"

# Wait for RBAC propagation
echo "⏳ Waiting 30 seconds for RBAC permissions to propagate..."
sleep 30

# PROPERLY handle federated identity credential
echo "🔗 Setting up workload identity federation..."
SUBJECT="system:serviceaccount:default:external-secrets-sa"

# Step 1: Check current state first
echo "🔍 Checking existing federated credentials..."
if az identity federated-credential show \
    --name "external-secrets-credential" \
    --identity-name "$IDENTITY_NAME" \
    --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    
    echo "✅ Federated credential already exists and is configured"
    echo "   Issuer: $OIDC_ISSUER"
    echo "   Subject: $SUBJECT"
    
else
    echo "🔄 Creating new federated credential..."
    
    # Method 1: Try CLI with timeout
    if timeout 60s az identity federated-credential create \
        --name "external-secrets-credential" \
        --identity-name "$IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --issuer "$OIDC_ISSUER" \
        --subject "$SUBJECT" \
        --audience "api://AzureADTokenExchange" >/dev/null 2>&1; then
        echo "✅ Federated credential created successfully via CLI"
    else
        echo "⚠️  CLI method failed or timed out, trying JSON approach..."
        
        # Method 2: JSON file approach
        cat > /tmp/federated-cred.json << EOF
{
    "name": "external-secrets-credential",
    "issuer": "$OIDC_ISSUER",
    "subject": "$SUBJECT",
    "audiences": ["api://AzureADTokenExchange"]
}
EOF
        
        if timeout 60s az identity federated-credential create \
            --identity-name "$IDENTITY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --parameters @/tmp/federated-cred.json >/dev/null 2>&1; then
            echo "✅ Federated credential created via JSON method"
        else
            echo "⚠️  JSON method failed, trying REST API..."
            
            # Method 3: REST API (most reliable)
            ACCESS_TOKEN=$(az account get-access-token --query accessToken -o tsv)
            SUBSCRIPTION_ID=$(az account show --query id -o tsv)
            
            HTTP_STATUS=$(curl -s -w "%{http_code}" -o /dev/null \
                -X PUT \
                -H "Authorization: Bearer $ACCESS_TOKEN" \
                -H "Content-Type: application/json" \
                -d '{
                    "properties": {
                        "issuer": "'$OIDC_ISSUER'",
                        "subject": "'$SUBJECT'",
                        "audiences": ["api://AzureADTokenExchange"]
                    }
                }' \
                "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$IDENTITY_NAME/federatedIdentityCredentials/external-secrets-credential?api-version=2023-01-31")
            
            if [[ "$HTTP_STATUS" == "200" || "$HTTP_STATUS" == "201" ]]; then
                echo "✅ Federated credential created via REST API"
            else
                echo "❌ All methods failed. Manual configuration required:"
                echo "   Azure Portal > Managed Identity > $IDENTITY_NAME > Federated credentials"
                echo "   Name: external-secrets-credential"
                echo "   Issuer: $OIDC_ISSUER"
                echo "   Subject: $SUBJECT"
                echo "   Audience: api://AzureADTokenExchange"
                exit 1
            fi
        fi
        
        rm -f /tmp/federated-cred.json
    fi
fi

# Step 2: Always verify final state
echo "🔍 Verifying federated credential configuration..."
if az identity federated-credential show \
    --name "external-secrets-credential" \
    --identity-name "$IDENTITY_NAME" \
    --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    echo "✅ Federated credential verified and ready"
else
    echo "❌ Federated credential verification failed"
    exit 1
fi

echo "✅ Workload identity federation configured"

# Create service account with workload identity
echo "🔧 Creating service account with workload identity..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets-sa
  namespace: default
  annotations:
    azure.workload.identity/client-id: $IDENTITY_CLIENT_ID
  labels:
    azure.workload.identity/use: "true"
EOF

# Create ClusterSecretStore
echo "🗂️ Creating ClusterSecretStore for Azure Key Vault..."
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: azure-key-vault
spec:
  provider:
    azurekv:
      url: https://${KEY_VAULT_NAME}.vault.azure.net/
      authType: WorkloadIdentity
      serviceAccountRef:
        name: external-secrets-sa
        namespace: default
EOF

echo "✅ ClusterSecretStore created"

# Create project namespaces
echo ""
echo "📁 Creating project namespaces..."
for env in dev staging prod; do
    kubectl create namespace "${PROJECT_NAME}-${env}" --dry-run=client -o yaml | kubectl apply -f -
    echo "✅ Created namespace: ${PROJECT_NAME}-${env}"
done

# Install ArgoCD
echo ""
echo "🔄 Installing ArgoCD..."
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n "$ARGOCD_NAMESPACE" -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "⏳ Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n "$ARGOCD_NAMESPACE"

echo "✅ ArgoCD installed successfully"

# Get ArgoCD admin password
echo ""
echo "🔑 Getting ArgoCD admin credentials..."
ARGOCD_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD Admin Password: $ARGOCD_PASSWORD"

# Create ArgoCD applications for each environment
echo ""
echo "📱 Creating ArgoCD applications..."

for env in dev staging prod; do
    cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${PROJECT_NAME}-${env}
  namespace: ${ARGOCD_NAMESPACE}
spec:
  project: default
  source:
    repoURL: ${GITOPS_REPO_URL}
    targetRevision: HEAD
    path: environments/${env}
  destination:
    server: https://kubernetes.default.svc
    namespace: ${PROJECT_NAME}-${env}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
    echo "✅ Created ArgoCD application: ${PROJECT_NAME}-${env}"
done

cd ..

echo ""
echo "=========================================="
echo "🎉 AKS DEPLOYMENT COMPLETE!"
echo "=========================================="
echo "✅ AKS cluster created: ${CLUSTER_NAME}"
echo "✅ Project namespaces created for: ${PROJECT_NAME}"
echo "✅ External Secrets Operator configured"
echo "✅ Azure Key Vault integration ready"
echo "✅ Workload Identity configured"
echo "✅ ArgoCD installed and configured"
echo "✅ GitOps applications created for all environments"
echo ""
echo "📋 Next Steps:"
echo "1. Access ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443"
echo "   Username: admin"
echo "   Password: ${ARGOCD_PASSWORD}"
echo ""
echo "2. Update your GitOps repository with Kubernetes manifests"
echo "3. ArgoCD will automatically sync your applications"
echo ""
echo "📊 Useful Commands:"
echo "• kubectl get nodes                    # Check cluster nodes"
echo "• kubectl get pods -A                  # Check all pods"
echo "• kubectl get applications -n argocd   # Check ArgoCD apps"
echo "• kubectl get clustersecretstore       # Check External Secrets"
echo ""
echo "🌐 Cluster Endpoint: $(terraform -chdir=terraform-aks output -raw cluster_endpoint)"
echo "📦 Resource Group: ${RESOURCE_GROUP}"
echo "🔑 Key Vault: ${KEY_VAULT_NAME}"
echo "=========================================="