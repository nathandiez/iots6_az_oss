#!/usr/bin/env bash
# deploy-aks.sh - Complete AKS deployment with all IoT services
set -e

echo "=========================================="
echo "Deploying Complete IoT Stack on AKS"
echo "=========================================="

# Check prerequisites
echo "Checking prerequisites..."
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI not found. Please install it first."
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Installing..."
    az aks install-cli
fi

if ! az account show &> /dev/null; then
    echo "❌ Not logged in to Azure. Please run: az login"
    exit 1
fi

if [[ ! -f ".env" ]]; then
    echo "❌ .env file not found. Please create it from .env.example"
    exit 1
fi

echo "✅ Prerequisites check passed"

# Load environment variables
echo "Loading environment variables..."
set -a
source .env
set +a

# Validate required variables
REQUIRED_VARS=("NAMESPACE" "POSTGRES_DB" "POSTGRES_USER" "POSTGRES_PASSWORD" "GRAFANA_ADMIN_USER" "GRAFANA_ADMIN_PASSWORD")
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var}" ]]; then
        echo "❌ Required environment variable $var is not set in .env"
        exit 1
    fi
done

echo "✅ Environment variables loaded"

# Source Azure environment variables
echo "Loading Azure environment..."
source ./set-azure-env.sh

# Deploy AKS cluster first
AKS_DIR="terraform-aks"
mkdir -p "$AKS_DIR"
cd "$AKS_DIR"

# Check if cluster already exists
if [[ -f "terraform.tfstate" ]]; then
    CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
    if [[ -n "$CLUSTER_NAME" ]]; then
        echo "📋 AKS cluster already exists: $CLUSTER_NAME"
        echo "Configuring kubectl access..."
        RESOURCE_GROUP=$(terraform output -raw resource_group_name)
        az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing
    fi
else
    # Deploy AKS cluster
    echo "🚀 Creating AKS cluster..."
    terraform init
    terraform plan
    
    echo ""
    read -p "Proceed with creating the AKS cluster? This will take 5-10 minutes (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Deployment cancelled."
        exit 0
    fi
    
    terraform apply -auto-approve
    
    # Get cluster credentials
    echo "Configuring kubectl access..."
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    RESOURCE_GROUP=$(terraform output -raw resource_group_name)
    az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing
fi

cd ..

# Wait for cluster to be ready
echo "⏳ Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo "📋 Cluster nodes:"
kubectl get nodes

# Function to substitute environment variables in YAML files
substitute_vars() {
    local file="$1"
    envsubst < "$file"
}

# Deploy IoT services in dependency order
echo ""
echo "🚀 Deploying IoT services to cluster..."

echo "1. Creating namespace..."
substitute_vars kubernetes/namespace/namespace.yaml | kubectl apply -f -

echo "2. Creating secrets..."
substitute_vars kubernetes/secrets/credentials.yaml | kubectl apply -f -

echo "3. Creating config maps..."
substitute_vars kubernetes/configmaps/timescaledb-init.yaml | kubectl apply -f -
substitute_vars kubernetes/configmaps/mosquitto-config.yaml | kubectl apply -f -

echo "4. Creating persistent volumes..."
substitute_vars kubernetes/storage/timescaledb-pvc.yaml | kubectl apply -f -
substitute_vars kubernetes/storage/mosquitto-pvc.yaml | kubectl apply -f -
substitute_vars kubernetes/storage/grafana-pvc.yaml | kubectl apply -f -

echo "5. Creating deployments..."
substitute_vars kubernetes/deployments/timescaledb.yaml | kubectl apply -f -
substitute_vars kubernetes/deployments/mosquitto.yaml | kubectl apply -f -
substitute_vars kubernetes/deployments/iot-service.yaml | kubectl apply -f -
substitute_vars kubernetes/deployments/grafana.yaml | kubectl apply -f -

echo "6. Creating services..."
substitute_vars kubernetes/services/timescaledb.yaml | kubectl apply -f -
substitute_vars kubernetes/services/mosquitto.yaml | kubectl apply -f -
substitute_vars kubernetes/services/grafana.yaml | kubectl apply -f -

echo "⏳ Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/timescaledb -n $NAMESPACE
kubectl wait --for=condition=available --timeout=300s deployment/mosquitto -n $NAMESPACE
kubectl wait --for=condition=available --timeout=300s deployment/iot-service -n $NAMESPACE
kubectl wait --for=condition=available --timeout=300s deployment/grafana -n $NAMESPACE

echo "📊 Checking deployment status..."
kubectl get pods -n $NAMESPACE
echo ""
kubectl get services -n $NAMESPACE

# Get external IPs
echo ""
echo "🌐 Getting external access information..."
echo "⏳ Waiting for LoadBalancer IPs (this may take a few minutes)..."

for service in timescaledb mosquitto grafana; do
    echo "Checking $service service..."
    for i in {1..20}; do
        EXTERNAL_IP=$(kubectl get service $service -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [[ -n "$EXTERNAL_IP" && "$EXTERNAL_IP" != "null" ]]; then
            case $service in
                timescaledb)
                    echo "✅ TimescaleDB: $EXTERNAL_IP:5432"
                    echo "   Connection: postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$EXTERNAL_IP:5432/$POSTGRES_DB"
                    ;;
                mosquitto)
                    echo "✅ Mosquitto MQTT: $EXTERNAL_IP:1883"
                    echo "   MQTT Broker: mqtt://$EXTERNAL_IP:1883"
                    ;;
                grafana)
                    echo "✅ Grafana Dashboard: $EXTERNAL_IP:3000"
                    echo "   Web UI: http://$EXTERNAL_IP:3000 ($GRAFANA_ADMIN_USER/$GRAFANA_ADMIN_PASSWORD)"
                    ;;
            esac
            break
        fi
        echo "⏳ $service IP pending... (attempt $i/20)"
        sleep 15
    done
    
    if [[ -z "$EXTERNAL_IP" || "$EXTERNAL_IP" == "null" ]]; then
        echo "⚠️  $service external IP not yet assigned"
    fi
done

echo ""
echo "=========================================="
echo "IoT Stack Deployment Complete!"
echo "=========================================="
echo "✅ AKS Cluster: $CLUSTER_NAME"
echo "✅ Namespace: $NAMESPACE"
echo "✅ All services deployed and running"
echo ""
echo "🧪 Test commands:"
echo "kubectl get all -n $NAMESPACE"
echo "kubectl logs -f deployment/iot-service -n $NAMESPACE"
echo "kubectl exec -it deployment/timescaledb -n $NAMESPACE -- psql -U $POSTGRES_USER -d $POSTGRES_DB"
echo ""
echo "📊 Monitor with: ./status.sh"
echo "🔍 Check IPs: kubectl get services -n $NAMESPACE"
echo "=========================================="