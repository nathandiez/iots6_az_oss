#!/usr/bin/env bash
# deploy.sh - Deployment script for xiots6
set -e

# Configuration
TARGET_HOSTNAME="nedv1-iots6"

# Check for --local-exec flag
USE_LOCAL_EXEC=false
if [ "$1" = "--local-exec" ]; then
    USE_LOCAL_EXEC=true
    echo "Starting deployment of $TARGET_HOSTNAME with integrated local-exec provisioners..."
else
    echo "Starting deployment of $TARGET_HOSTNAME with manual deployment..."
fi

# Source Proxmox environment variables
source ./set-proxmox-env.sh

# Change to terraform directory
cd "$(dirname "$0")/terraform"

# Initialize and apply Terraform
echo "Initializing Terraform..."
terraform init

echo "Creating/updating infrastructure..."
if [ "$USE_LOCAL_EXEC" = true ]; then
    terraform apply -var="enable_local-exec=true" -auto-approve
    DEPLOYMENT_METHOD="integrated provisioners"
    SERVICE_IP="Check the terraform output above for IP and service details"
else
    terraform apply -var="enable_local-exec=false" -auto-approve
    DEPLOYMENT_METHOD="manual deployment with Ansible"
    
    # Manual deployment logic
    echo "Waiting for VM to initialize and get an IP address..."
    sleep 1

    # Get the IP address using multiple methods
    get_ip() {
      # Method 1: Extract from terraform state directly using JSON
      local ip=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.child_modules[].resources[] | select(.type=="proxmox_virtual_environment_vm") | .values.ipv4_addresses[0][0]' 2>/dev/null || echo "")
      
      # Check if it's valid
      if [ -n "$ip" ] && [ "$ip" != "null" ] && [ "$ip" != "127.0.0.1" ]; then
        echo "$ip"
        return 0
      fi
      
      # Method 2: Extract from terraform show text output
      ip=$(terraform refresh > /dev/null 2>&1; terraform show | grep -A 5 "ipv4_addresses" | grep -o -E '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '127.0.0.1' | head -n 1)
      
      if [ -n "$ip" ]; then
        echo "$ip"
        return 0
      fi
      
      # Method 3: Try DNS resolution
      ip=$(ping -c 1 ${TARGET_HOSTNAME}.local 2>/dev/null | head -n 1 | grep -o -E '([0-9]{1,3}\.){3}[0-9]{1,3}')
      
      if [ -n "$ip" ]; then
        echo "$ip"
        return 0
      fi
      
      # If all else fails
      echo ""
      return 1
    }

    # Try multiple times to get a valid IP
    for i in {1..10}; do
      echo "Attempt $i to get IP address..."
      IP=$(get_ip)
      
      if [ -n "$IP" ]; then
        echo "Found IP: $IP"
        break
      fi
      
      echo "No valid IP found, waiting before trying again..."
      sleep 5
    done

    # Validate IP address
    if [ -z "$IP" ]; then
      echo "Error: Could not retrieve a valid IP address for $TARGET_HOSTNAME."
      echo "You may need to check the Proxmox web UI or console to see what's happening."
      exit 1
    fi

    echo "VM IP address: $IP"

    # Update Ansible inventory
    cd ../ansible
    sed -i '' "s/ansible_host=.*/ansible_host=$IP/" inventory/hosts

    # Wait for SSH to become available
    echo "Waiting for SSH to become available..."
    MAX_SSH_WAIT=300 # 5 minutes
    START_TIME=$(date +%s)

    while true; do
      if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 nathan@"$IP" echo ready 2>/dev/null; then
        echo "SSH is available!"
        break
      fi
      
      # Check if we've waited too long
      CURRENT_TIME=$(date +%s)
      ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
      
      if [ $ELAPSED_TIME -gt $MAX_SSH_WAIT ]; then
        echo "Timed out waiting for SSH. You may need to check the VM console."
        exit 1
      fi
      
      echo "Still waiting for SSH..."
      sleep 10
    done

    # Run Ansible playbook
    echo "Running Ansible to configure the server..."
    ansible-playbook playbooks/main.yml

    # Test the services
    sleep 10
    echo "Testing services..."
    # Test TimescaleDB connectivity
    echo "Testing TimescaleDB connection..."
    if ssh -o StrictHostKeyChecking=no nathan@"$IP" "PGPASSWORD=iotpass psql -h localhost -U iotuser -d iotdb -c 'SELECT 1;'" 2>/dev/null; then
        echo "✅ TimescaleDB is responding"
    else
        echo "⚠️  TimescaleDB may still be starting up"
    fi
    
    # Test MQTT broker
    echo "Testing MQTT broker..."
    if nc -z -w5 "$IP" 1883 2>/dev/null; then
        echo "✅ MQTT broker port is accessible"
    else
        echo "⚠️  MQTT broker may still be starting up"
    fi
    
    # Check Docker containers
    echo "Checking service status..."
    ssh -o StrictHostKeyChecking=no nathan@"$IP" "docker ps --format 'table {{.Names}}\t{{.Status}}'" || echo "Could not check container status"
    
    # Set variables for final summary
    SERVICE_IP="$IP"

    echo ""
    echo "DEPLOYMENT COMPLETE!"

    echo "✅ VM created/configured in Proxmox with $DEPLOYMENT_METHOD"
    if [ "$USE_LOCAL_EXEC" = false ]; then
        echo "✅ IoT Infrastructure Services:"
        echo "   • TimescaleDB: postgresql://iotuser:iotpass@$SERVICE_IP:5432/iotdb"
        echo "   • MQTT Broker: mqtt://$SERVICE_IP:1883"
        echo "   • SSH Access: nathan@$SERVICE_IP"
        echo "✅ Server IP: $SERVICE_IP"
    else
        echo "✅ $SERVICE_IP"
    fi
fi
cd ..
./taillogs.sh