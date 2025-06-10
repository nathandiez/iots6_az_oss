#!/usr/bin/env bash
# deploy-aks.sh - Azure AKS deployment script for IoTS6 (Production GitOps)
set -e

echo "=========================================="
echo "Deploying IoT Stack to Azure AKS with GitOps"
echo "=========================================="

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
export TF_VAR_node_count="$AKS_NODE_COUNT"
export TF_VAR_node_size="$AKS_NODE_SIZE"

# Validate required variables
REQUIRED_VARS=("AKS_NAMESPACE" "POSTGRES_DB" "POSTGRES_USER" "POSTGRES_PASSWORD" "GRAFANA_ADMIN_USER" "GRAFANA_ADMIN_PASSWORD" "AZURE_LOCATION" "CLUSTER_NAME" "ARGOCD_VERSION" "ARGOCD_NAMESPACE" "PROJECT_NAME" "KEY_VAULT_NAME" "DATADOG_API_KEY")
for var in "${REQUIRED_VARS[@]}"; do
   if [[ -z "${!var}" ]]; then
       echo "❌ Required environment variable $var is not set in .env"
       exit 1
   fi
done

# Check prerequisites
if ! az account show &> /dev/null; then
    echo "❌ Not logged in to Azure. Please run: az login"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "❌ helm not found. Please install helm"
    exit 1
fi

echo "✅ Prerequisites check passed"
echo "📋 Using cluster: $CLUSTER_NAME in region: $AZURE_LOCATION"

# Get Azure subscription and tenant info
AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)

# Create Key Vault and store configuration
echo ""
echo "📦 Creating Azure Key Vault and storing configuration..."
az group create --name "$RESOURCE_GROUP" --location "$AZURE_LOCATION" 2>/dev/null || true

# Create Key Vault
az keyvault create \
  --name "$KEY_VAULT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$AZURE_LOCATION" \
  --enable-rbac-authorization false \
  2>/dev/null || echo "Key Vault already exists"

# Store secrets in Key Vault
echo "Storing secrets in Key Vault..."
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "postgres-db" --value "$POSTGRES_DB" >/dev/null
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "postgres-user" --value "$POSTGRES_USER" >/dev/null
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "postgres-password" --value "$POSTGRES_PASSWORD" >/dev/null
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "grafana-admin-user" --value "$GRAFANA_ADMIN_USER" >/dev/null
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "grafana-admin-password" --value "$GRAFANA_ADMIN_PASSWORD" >/dev/null
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "datadog-api-key" --value "$DATADOG_API_KEY" >/dev/null
echo "✅ Secrets stored in Azure Key Vault"

# Source Azure environment variables
if [[ -f "./set-azure-env.sh" ]]; then
    source ./set-azure-env.sh
fi

# Deploy AKS cluster
AKS_DIR="terraform-aks"
cd "$AKS_DIR"

if az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    TERRAFORM_CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
    if [[ -n "$TERRAFORM_CLUSTER_NAME" ]]; then
        echo "📋 AKS cluster already exists: $TERRAFORM_CLUSTER_NAME"
        CLUSTER_NAME="$TERRAFORM_CLUSTER_NAME"  # Use existing cluster name
    fi
else
    echo "🚀 Creating AKS cluster..."
    terraform init
    terraform plan \
        -var="cluster_name=$CLUSTER_NAME" \
        -var="location=$AZURE_LOCATION" \
        -var="resource_group=$RESOURCE_GROUP" \
        -var="node_count=$AKS_NODE_COUNT" \
        -var="node_size=$AKS_NODE_SIZE"
    
    terraform apply -auto-approve \
        -var="cluster_name=$CLUSTER_NAME" \
        -var="location=$AZURE_LOCATION" \
        -var="resource_group=$RESOURCE_GROUP" \
        -var="node_count=$AKS_NODE_COUNT" \
        -var="node_size=$AKS_NODE_SIZE"
    CLUSTER_NAME=$(terraform output -raw cluster_name)
fi

# Configure kubectl access
echo "Configuring kubectl access..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

cd ..

# Wait for cluster ready
echo "⏳ Waiting for cluster nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=600s
echo "   ✅ All nodes are ready"

# Install External Secrets Operator
echo ""
echo "🔐 Installing External Secrets Operator..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace \
  --set installCRDs=true \
  --wait --timeout=300s

# Wait for CRDs to be registered
echo "⏳ Waiting for External Secrets CRDs to be ready..."
for i in {1..60}; do
    if kubectl get crd clustersecretstores.external-secrets.io &>/dev/null && \
       kubectl get crd externalsecrets.external-secrets.io &>/dev/null; then
        echo "   ✅ External Secrets CRDs are ready"
        break
    fi
    
    if [[ $i -eq 60 ]]; then
        echo "   ❌ External Secrets CRDs not found after 5 minutes"
        exit 1
    fi
    
    echo "   Waiting for CRDs... (attempt $i/60)"
    sleep 5
done

# Create Workload Identity for External Secrets
echo "🔑 Setting up Workload Identity for External Secrets..."

# Get AKS OIDC Issuer
AKS_OIDC_ISSUER=$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --query "oidcIssuerProfile.issuerUrl" -o tsv)

# Create managed identity
IDENTITY_NAME="id-${CLUSTER_NAME}-external-secrets"
az identity create --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --location "$AZURE_LOCATION" 2>/dev/null || echo "Identity already exists"

# Get identity details
IDENTITY_CLIENT_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv)
IDENTITY_PRINCIPAL_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)

# Grant Key Vault permissions
echo "   Granting Key Vault permissions..."
az keyvault set-policy \
  --name "$KEY_VAULT_NAME" \
  --object-id "$IDENTITY_PRINCIPAL_ID" \
  --secret-permissions get list >/dev/null

# Create federated credential
echo "   Creating federated credential..."
az identity federated-credential create \
  --name "external-secrets-federated" \
  --identity-name "$IDENTITY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --issuer "$AKS_OIDC_ISSUER" \
  --subject "system:serviceaccount:external-secrets-system:external-secrets" \
  --audience "api://AzureADTokenExchange" 2>/dev/null || echo "Federated credential already exists"

# Annotate the service account
echo "   Annotating service account..."
kubectl annotate serviceaccount external-secrets \
  -n external-secrets-system \
  azure.workload.identity/client-id="$IDENTITY_CLIENT_ID" \
  --overwrite

kubectl label serviceaccount external-secrets \
  -n external-secrets-system \
  azure.workload.identity/use="true" \
  --overwrite

# Restart External Secrets pods
kubectl rollout restart deployment -n external-secrets-system

echo "✅ External Secrets Operator configured with Azure Key Vault"

# Deploy External Secrets configuration using Helm
echo ""
echo "📋 Deploying External Secrets configuration with Helm..."
sleep 10  # Give API server time to register CRDs

helm upgrade --install external-secrets-config ./external-secrets-config \
    --set global.projectName="$PROJECT_NAME" \
    --set global.keyVaultName="$KEY_VAULT_NAME" \
    --set global.tenantId="$AZURE_TENANT_ID" \
    --create-namespace \
    --wait --timeout=300s

# Wait for External Secrets to sync
echo "⏳ Waiting for External Secrets to sync..."
sleep 15

# Install ArgoCD
echo ""
echo "🚀 Installing ArgoCD..."
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n "$ARGOCD_NAMESPACE" -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n "$ARGOCD_NAMESPACE"
ARGOCD_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
kubectl patch svc argocd-server -n "$ARGOCD_NAMESPACE" -p '{"spec": {"type": "LoadBalancer"}}'
echo "✅ ArgoCD installed - Username: admin, Password: $ARGOCD_PASSWORD"

# Deploy ArgoCD ApplicationSet
echo ""
echo "🎯 Setting up GitOps deployment..."
kubectl apply -f argocd/applicationsets/iot-environments.yaml
echo "✅ ArgoCD ApplicationSet deployed!"

# Wait for ArgoCD to sync
echo ""
echo "⏳ Waiting for ArgoCD to sync the applications..."
echo "   This may take 5-10 minutes for all services to start..."
sleep 30

# Check application status
for i in {1..20}; do
    APP_STATUS=$(kubectl get application iot-stack-dev -n "$ARGOCD_NAMESPACE" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    APP_HEALTH=$(kubectl get application iot-stack-dev -n "$ARGOCD_NAMESPACE" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    
    echo "   ArgoCD Application (dev) - Sync: $APP_STATUS, Health: $APP_HEALTH (attempt $i/20)"
    
    if [[ "$APP_STATUS" == "Synced" && "$APP_HEALTH" == "Healthy" ]]; then
        echo "   ✅ ArgoCD dev application is synced and healthy"
        break
    fi
    
    sleep 30
done

# Final status checks
echo ""
echo "🔍 Checking External Secrets status..."
kubectl get externalsecrets -A
kubectl get secrets -n ${PROJECT_NAME}-dev | grep iot-secrets || echo "   Secrets still being created..."

echo ""
echo "🌐 Getting service endpoints (dev environment)..."
kubectl get services -n ${PROJECT_NAME}-dev 2>/dev/null || echo "   Services not yet created"

echo ""
echo "📊 Final status check (dev environment)..."
kubectl get all -n ${PROJECT_NAME}-dev 2>/dev/null || echo "   Resources not yet created"

echo ""
echo "=========================================="
echo "Production GitOps IoT Stack Deployment Complete!"
echo "=========================================="
echo "✅ AKS Cluster: $CLUSTER_NAME"
echo "✅ Region: $AZURE_LOCATION"
echo "✅ Project Name: $PROJECT_NAME"
echo "✅ External Secrets: Fetching from Azure Key Vault"
echo "✅ Environments: ${PROJECT_NAME}-dev, ${PROJECT_NAME}-staging, ${PROJECT_NAME}-prod"
echo "✅ Storage: managed-csi (Azure Disk)"
echo ""
echo "🎯 ArgoCD: Username=admin, Password=$ARGOCD_PASSWORD"
echo "   Namespace: $ARGOCD_NAMESPACE"
echo "   Version: $ARGOCD_VERSION"
echo "   Applications: iot-stack-dev, iot-stack-staging, iot-stack-prod"
echo ""
echo "🔐 Security: No secrets committed to Git!"
echo "   Configuration stored in Azure Key Vault: $KEY_VAULT_NAME"
echo "   External Secrets Operator manages secret injection"
echo ""
echo "📦 Helm deployments:"
echo "   - External Secrets Operator: external-secrets-system namespace"
echo "   - External Secrets Config: external-secrets-config"
echo ""
echo "🔍 Monitor GitOps deployment:"
echo "   kubectl get applications -n $ARGOCD_NAMESPACE"
echo "   kubectl get externalsecrets -A"
echo "   kubectl get secrets -n ${PROJECT_NAME}-dev | grep iot-secrets"
echo "   helm list -A"
echo ""
echo "🌐 Check all environments:"
echo "   kubectl get all -n ${PROJECT_NAME}-dev"
echo "   kubectl get all -n ${PROJECT_NAME}-staging"
echo "   kubectl get all -n ${PROJECT_NAME}-prod"
echo ""
echo "🌐 ArgoCD UI will be available once LoadBalancer is provisioned (~5 minutes)"
echo "🚀 IoT services deployed via production GitOps with External Secrets!"
echo "=========================================="