#!/usr/bin/env bash
# set-azure-env.sh - Set up Azure environment for IoTS6 deployment
echo "Setting up Azure environment for aziots6..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI not found. Please install it first:"
    echo "   https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if we're logged in to Azure
if ! az account show &> /dev/null; then
    echo "❌ Not logged in to Azure. Please run: az login"
    exit 1
fi

# Get current subscription info
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)

echo "✅ Azure CLI ready"
echo "📋 Current subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

# Check if SSH key exists
SSH_KEY_PATH="$HOME/.ssh/id_rsa_azure"
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "🔑 Creating Azure SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "aziots6-azure-key"
    echo "✅ SSH key pair created at $SSH_KEY_PATH"
else
    echo "✅ SSH key pair already exists at $SSH_KEY_PATH"
fi

# Export environment variables for Terraform
export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"

# Optional: Set specific location if needed
export TF_VAR_location="East US"

echo "✅ Azure environment configured for IoTS6 deployment"
echo "🚀 Ready to run: ./deploy.sh"