#!/usr/bin/env bash
# wait-for-ssh.sh - Wait for Azure VM to be accessible via SSH and update Ansible inventory
set -e

echo "Waiting for SSH to become available..."
max_attempts=30
attempt=0

# Ensure we're in the terraform directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"
cd "$TERRAFORM_DIR"

# Function to get IP from terraform output
get_ip() {
  local ip=$(terraform output -raw vm_ip 2>/dev/null || echo "")
  
  if [ -n "$ip" ] && [ "$ip" != "null" ]; then
    echo "$ip"
    return 0
  fi
  
  echo ""
  return 1
}

# Get IP address with retries
for i in {1..5}; do
  IP=$(get_ip)
  if [ -n "$IP" ]; then
    break
  fi
  echo "IP detection attempt $i failed, waiting 10 seconds..."
  sleep 10
done

if [ -z "$IP" ]; then
  echo "Error: Could not retrieve a valid IP address after multiple attempts"
  echo "Debug: Trying terraform refresh..."
  terraform refresh
  IP=$(get_ip)
fi

if [ -z "$IP" ]; then
  echo "Error: Still could not retrieve a valid IP address"
  echo "Debug info:"
  terraform output || echo "No outputs available"
  exit 1
fi

echo "Using IP: $IP"

# Update Ansible inventory with correct IP
# Create hosts file directory if it doesn't exist
mkdir -p ../ansible/inventory
echo "Updating Ansible inventory with IP: $IP"
cat > ../ansible/inventory/hosts << EOF
[iot_servers]
aziots6 ansible_host=$IP

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_user=nathan
ansible_ssh_private_key_file=~/.ssh/id_rsa_azure
EOF

# Now wait for SSH
while [ $attempt -lt $max_attempts ]; do
  if ssh -i ~/.ssh/id_rsa_azure -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 nathan@"$IP" echo ready 2>/dev/null; then
    echo "SSH is available!"
    break
  fi
  attempt=$((attempt + 1))
  echo "Attempt $attempt/$max_attempts - Still waiting for SSH..."
  sleep 10
done

if [ $attempt -eq $max_attempts ]; then
  echo "Timed out waiting for SSH"
  exit 1
fi