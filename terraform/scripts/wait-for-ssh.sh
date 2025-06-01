#!/usr/bin/env bash
# wait-for-ssh.sh - Wait for VM to be accessible via SSH and update Ansible inventory
set -e

echo "Waiting for SSH to become available..."
max_attempts=30
attempt=0

# Function to get IP with multiple methods
get_ip() {
  # Method 1: Extract from terraform state directly
  local ip=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.child_modules[].resources[] | select(.type=="proxmox_virtual_environment_vm") | .values.ipv4_addresses[0][0]' 2>/dev/null || echo "")
  
  # Check if it's valid
  if [ -n "$ip" ] && [ "$ip" != "null" ] && [ "$ip" != "127.0.0.1" ]; then
    echo "$ip"
    return 0
  fi
  
  # Method 2: Extract from terraform show text output
  ip=$(terraform show 2>/dev/null | grep -A 5 "ipv4_addresses" | grep -o -E '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '127.0.0.1' | head -n 1)
  
  if [ -n "$ip" ]; then
    echo "$ip"
    return 0
  fi
  
  # Method 3: Try DNS resolution as fallback
  ip=$(ping -c 1 nedv1-iots6.local 2>/dev/null | head -n 1 | grep -o -E '([0-9]{1,3}\.){3}[0-9]{1,3}' || echo "")
  
  if [ -n "$ip" ]; then
    echo "$ip"
    return 0
  fi
  
  echo ""
  return 1
}

# Get IP address with retries
for i in {1..3}; do
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
  terraform show | grep -A 10 -B 5 ipv4_addresses || echo "No IP addresses found in state"
  exit 1
fi

echo "Using IP: $IP"

# Create hosts file directory if it doesn't exist
mkdir -p ../ansible/inventory
echo "Updating Ansible inventory with IP: $IP"
cat > ../ansible/inventory/hosts << EOF
[iot_servers]
nedv1-iots6 ansible_host=$IP

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOF

# Now wait for SSH
while [ $attempt -lt $max_attempts ]; do
  if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 nathan@"$IP" echo ready 2>/dev/null; then
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