#!/usr/bin/env bash
# destroy.sh - Complete teardown script
# WARNING: This will completely destroy the VM and all Terraform state!
set -e

echo "=========================================="
echo "WARNING: DESTRUCTIVE OPERATION"
echo "=========================================="
echo "This will:"
echo "  - Destroy the IoT infrastructure VM in Proxmox"
echo "  - Delete all Terraform state files"
echo "  - Clean up lock files"
echo "  - Reset everything to a clean slate"
echo ""
echo "Target VM: your-target-hostname"
echo "Services to be destroyed:"
echo "  • TimescaleDB database and all data"
echo "  • Mosquitto MQTT broker"
echo "  • IoT data processing services"
echo "  • All Docker containers and networks"
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
echo "Starting destruction process..."

# Source Proxmox environment variables
echo "Loading Proxmox environment..."
source ./set-proxmox-env.sh

# Change to terraform directory
cd "$(dirname "$0")/terraform"

# Check if terraform state exists
if [[ -f "terraform.tfstate" ]]; then
  echo ""
  echo "Terraform state found. Destroying infrastructure..."
  
  # Initialize terraform (in case .terraform directory is missing)
  terraform init -upgrade
  
  # Destroy the infrastructure
  echo "Running terraform destroy..."
  terraform destroy -auto-approve
  
  echo "Infrastructure destroyed successfully."
else
  echo "No terraform.tfstate found. Skipping terraform destroy."
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
  sed -i '' 's/ansible_host=.*/ansible_host=PLACEHOLDER/' inventory/hosts
  echo "Ansible inventory reset to placeholder state."
fi

echo ""
echo "=========================================="
echo "DESTRUCTION COMPLETE"
echo "=========================================="
echo "✅ infrastructure VM destroyed in Proxmox"
echo "✅ TimescaleDB and all sensor data deleted"
echo "✅ MQTT broker and message history removed"
echo "✅ All Docker containers and networks destroyed"
echo "✅ Terraform state files deleted"
echo "✅ Terraform lock files removed"
echo "✅ Provider cache cleared"
echo "✅ Ansible inventory reset"
echo ""
echo "You can now run deploy.sh to start fresh!"
echo "=========================================="