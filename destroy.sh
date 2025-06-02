#!/usr/bin/env bash
# destroy.sh - Complete Azure teardown script
# WARNING: This will completely destroy the VM and all Terraform state!
set -e

echo "=========================================="
echo "WARNING: DESTRUCTIVE OPERATION"
echo "=========================================="
echo "This will:"
echo "  - Destroy the Azure IoT infrastructure VM"
echo "  - Delete all Terraform state files"
echo "  - Clean up lock files"
echo "  - Reset everything to a clean slate"
echo ""
echo "Target VM: aziots6"
echo "Azure Resources to be destroyed:"
echo "  • Virtual Machine (Standard_B2s)"
echo "  • Public IP address (static)"
echo "  • Network interfaces and security groups"
echo "  • Virtual network and subnets"
echo "  • Resource group: rg-aziots6"
echo ""
echo "Services to be destroyed:"
echo "  • TimescaleDB database and all data"
echo "  • Mosquitto MQTT broker"
echo "  • IoT data processing services"
echo "  • All Docker containers and networks"
echo ""
echo "This action is IRREVERSIBLE!"
echo "Billing will stop after resource deletion."
echo "=========================================="

# Prompt for confirmation
read -p "Are you sure you want to proceed? (type 'yes' to continue): " confirmation

if [[ "$confirmation" != "yes" ]]; then
  echo "Operation cancelled."
  exit 0
fi

echo ""
echo "Starting destruction process..."

# Source Azure environment variables
echo "Loading Azure environment..."
source ./set-azure-env.sh

# Change to terraform directory
cd "$(dirname "$0")/terraform"

# Get VM IP for cleanup (before destroying)
echo ""
echo "Getting VM information for cleanup..."
VM_IP=$(terraform output -raw vm_ip 2>/dev/null || echo "")

# Check if terraform state exists
if [[ -f "terraform.tfstate" ]]; then
  echo ""
  echo "Terraform state found. Destroying Azure infrastructure..."
  
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
  
  # Destroy the infrastructure
  echo "Running terraform destroy..."
  terraform destroy -auto-approve
  
  echo "Azure infrastructure destroyed successfully."
else
  echo "No terraform.tfstate found. Skipping terraform destroy."
fi

# Clean up SSH known_hosts
echo ""
echo "Cleaning up SSH known_hosts..."
if [[ -n "$VM_IP" ]] && [[ "$VM_IP" != "null" ]]; then
  ssh-keygen -R "$VM_IP" 2>/dev/null || true
  echo "✅ Cleaned up SSH entry for $VM_IP"
fi

# Clean up all Terraform files
echo ""
echo "Cleaning up Terraform state and lock files..."

# Remove state files
rm -f terraform.tfstate
rm -f terraform.tfstate.backup

# Remove lock file if it exists
rm -f .terraform.lock.hcl

# Remove .terraform directory (contains providers and modules)
rm -rf .terraform

echo "All Terraform files cleaned up."

# Optional: Clean up Ansible inventory
echo ""
echo "Resetting Ansible inventory..."
cd ../ansible

# Reset the inventory to a default state (remove the IP)
if [[ -f "inventory/hosts" ]]; then
  cat > inventory/hosts << EOF
[iot_servers]
aziots6 ansible_host=PLACEHOLDER

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_user=nathan
ansible_ssh_private_key_file=~/.ssh/id_rsa_azure
EOF
  echo "Ansible inventory reset to placeholder state."
fi

echo ""
echo "=========================================="
echo "DESTRUCTION COMPLETE"
echo "=========================================="
echo "✅ Azure VM destroyed (aziots6)"
echo "✅ TimescaleDB and all sensor data deleted"
echo "✅ MQTT broker and message history removed"
echo "✅ All Docker containers and networks destroyed"
echo "✅ Public IP address released"
echo "✅ Network security groups deleted"
echo "✅ Virtual network and subnets removed"
echo "✅ Resource group (rg-aziots6) deleted"
echo "✅ Azure billing stopped for these resources"
echo "✅ Terraform state files deleted"
echo "✅ Terraform lock files removed"
echo "✅ Provider cache cleared"
echo "✅ SSH known_hosts cleaned up"
echo "✅ Ansible inventory reset"
echo ""
echo "💰 All Azure costs for this deployment have stopped"
echo "🚀 You can now run ./deploy.sh to start fresh!"
echo "=========================================="