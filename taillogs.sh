#!/usr/bin/env bash
# taillogs.sh - Tail serve_config logs with SSH key management

# Get VM IP from terraform state
cd terraform

# Debug: Check if we're in the right directory and state exists
if [ ! -f "terraform.tfstate" ]; then
    echo "Error: terraform.tfstate not found in $(pwd)"
    echo "Make sure you've run deploy.sh first"
    cd ..
    exit 1
fi

# Try to get the VM IP
VM_IP=$(terraform output -raw vm_ip 2>/dev/null)

# If that didn't work, try the old name
if [ -z "$VM_IP" ] || [ "$VM_IP" = "Not yet available - VM may still be starting" ]; then
    VM_IP=$(terraform output -raw server_ip 2>/dev/null)
fi

cd ..

if [ -z "$VM_IP" ] || [ "$VM_IP" = "Not yet available - VM may still be starting" ]; then
    echo "Error: Could not get VM IP from terraform output"
    echo "Available outputs:"
    cd terraform && terraform output && cd ..
    exit 1
fi

echo "Connecting to VM at $VM_IP..."

# Remove old SSH key for this IP
echo "Cleaning up old SSH key..."
ssh-keygen -R $VM_IP 2>/dev/null || true

# Tail the logs
echo "Tailing IoT service and Mosquitto logs (Ctrl+C to stop)..."
ssh -o StrictHostKeyChecking=accept-new your_ansible_user@$VM_IP 'bash -s' << 'EOF'
    docker logs -f iot_service 2>&1 | while IFS= read -r line; do
        echo "[IOT] $line"
    done &
    
    docker logs -f mosquitto 2>&1 | while IFS= read -r line; do
        echo "[MQTT] $line"  
    done &
    
    # This will keep the script running until both background processes end
    wait
EOF